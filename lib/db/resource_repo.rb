module Db
    class ResourceRepo
        include App::Import["db.connection"]

        def resources = connection[:resources]

        COL_ID        = Sequel[:resource_paths][:id]
        COL_FULLPATH  = Sequel[:resource_paths][:fullpath]

        def for_path(path)
            return connection[:resource_ephemeral_root] if path == ""

            resources.where(id:
                resources
                    .select(COL_ID)
                    .join(:resource_paths, id: :id)
                    .where(COL_FULLPATH => path&.chomp("/"))
            )
        end

        def clone_tree source_id, dest_id, name
            connection[<<~SQL, { source_id: source_id, dest_id: dest_id, name: name }].insert
                    -- get the source branch nodes into a cte

                with 
                recursive cte_to_copy as (
                    -- base - root of the branch to copy
                    select id, pid, :name as path, is_coll, mime, content
                    from resources where id = :source_id
                    union
                    -- recursive - children of the previously selected nodes
                    select r.*
                    from resources as r
                    join cte_to_copy as c on r.pid = c.id
                ),

                    -- then, generate new ids for the nodes we're copying 
                    -- separate CTE, since window functions don't work in recursive ctes
                    -- TODO: if this was a UUID table, we could generate the new id in the first cte

                cte_with_new_ids as (
                    select
                        row_number() over (order by id) + (select max(id) from resources) as newid,
                        cte_to_copy.*
                    from cte_to_copy
                ),

                    -- finally, since we recorded the original id/pid and have the new id,
                    -- we can join and use the correct new id for the parent relationship
                    -- if new pid is null (from left join), it's the top-level, and it gets set to the destination

                cte_with_fixed_pids as (
                    select
                        a.newid as newid,
                        coalesce(b.newid, :dest_id) as newpid,
                        a.*
                    from cte_with_new_ids a
                    left join cte_with_new_ids b on a.pid = b.id
                )

                    -- now, just select into the actual table

                insert into resources (id, pid, path, is_coll, mime, content)
                select newid, newpid, path, is_coll, mime, content from cte_with_fixed_pids;
            SQL
        end

    end
end