module Db
  class ResourceRepo
    include App::Import["db.connection"]

    def resources = connection[:resources]

    COL_ID = Sequel[:resource_paths][:id]
    COL_FULLPATH = Sequel[:resource_paths][:fullpath]

    def at_path path
      return connection[:resource_ephemeral_root] if path == ""

      connection[:resources].where(id:
          connection[:resources]
              .select(Sequel[:resources][:id])
              .join(:resource_paths, id: :id)
              .where(Sequel[:resource_paths][:path] => path&.chomp("/")))
    end

    def move_tree source_id, dest_id, name
      resources.where(id: source_id).update(pid: dest_id, path: name)
    end

    def clone_tree source_id, dest_id, name
      connection[<<~SQL, {source_id: source_id, dest_id: dest_id, name: name}].insert
            -- get the source branch nodes into a cte

        with 
        recursive cte_descendants as (
            -- base - root of the branch to copy (renamed)
            select uuid() as newid, resources.*
            from resources where id = :source_id
            union
            -- recursive - children of the previously selected nodes
            select uuid() as newid, resources.*
            from resources
            join cte_descendants as c on resources.pid = c.id
        ),

            -- now, since we've recorded the original id/pid and have the new uuid,
            -- we can join and use the correct new id for the parent relationship
            -- if new pid is null (from left join), it's the top-level, and it gets set to the destination

        cte_fixed_pids as (
            select
                coalesce(parent.newid, :dest_id) as newpid,
                case when parent.id is null 
                    then :name 
                    else child.path 
                end as newpath,
                child.*
            from      cte_descendants child
            left join cte_descendants parent on child.pid = parent.id
        )

            -- now, just select into the actual tables

        insert into resources 
        select
            fixed.newid,
            fixed.newpid,
            fixed.newpath,

            fixed.coll,
            fixed.type,
            fixed.length,
            fixed.content,
            fixed.etag,
            datetime('now'),
            null
        from cte_fixed_pids as fixed;
      SQL
    end
  end
end
