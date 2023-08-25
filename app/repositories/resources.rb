module Repositories
  class Resources
    include App::Import["db.connection"]

    def resources = connection[:resources]
    def properties = connection[:properties]

    COL_ID = Sequel[:resource_paths][:id]
    COL_FULLPATH = Sequel[:resource_paths][:fullpath]

    UUID_FUN = Sequel.function(:uuid)
    NOW_FUN  = Sequel.lit("datetime('now')")

    def at_path path
      return connection[:resource_ephemeral_root] if path == ""

      connection[:resources].where(id:
          connection[:resources]
              .select(Sequel[:resources][:id])
              .join(:resource_paths, id: :id)
              .where(Sequel[:resource_paths][:path] => path&.chomp("/")))
    end

    def with_descendants(rid, depth:)
      tree_descendants_cte(rid, depth)
        .join(:resources, id: :id)
        .select_all(:resources)
        .select_append(Sequel[:desc][:path].as(:fullpath), :depth)
    end

    def move_tree source_id, dest_id, name
      resources
        .where(id: source_id)
        .update(pid: dest_id, path: name, updated_at: NOW_FUN)
    end

    def clone_tree source_id, dest_id, name
      tree_clone_preparedstmt 
        .call(source_id: source_id, dest_id: dest_id, name: name)
    end

    def insert pid:, path:, **data
      data = blobify_data_content data
      opts = data.merge(
        id: UUID_FUN,
        pid: pid,
        path: path,
        created_at: NOW_FUN
      )

      resources.insert(**opts)
    end

    def update id:, **data
      data = blobify_data_content data
      opts = data.merge(
        updated_at: NOW_FUN
      )

      resources.where(id: id).update(**opts)
    end

    def delete id:
      # cascades in the database to delete children
      resources.where(id: id).delete
    end

    private

    def blobify_data_content data
      return data unless data.key? :content
      return data if data[:content].nil?

      data.merge(content: Sequel::SQL::Blob.new(data[:content]))
    end

    def tree_descendants_cte root_id, depth
      connection[:desc].with_recursive(:desc, 
        connection[:resource_paths]
          .select(:id, :path, Sequel[0].as(:depth))
          .where(id: root_id),
        connection[:resources]
          .select(
            Sequel[:resources][:id], 
            Sequel[:desc][:fullpath] + "/" + Sequel[:resources][:path],
            Sequel[:desc][:depth] + 1
          )
          .join(:desc, id: :pid)
          .where(Sequel[:depth] <= depth),
        args: [:id, :fullpath, :depth]
      ).select_all(:desc)
    end

    def tree_clone_preparedstmt
      @clone_tree_preparedstmt ||= connection[<<~SQL].prepare(:insert, :tree_clone)
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
