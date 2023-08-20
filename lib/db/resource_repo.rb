module Db
    class ResourceRepo
        include App::Import["db.connection"]

        def resources = connection[:resources]

        COL_ID        = Sequel[:resource_paths][:id]
        COL_FULLPATH  = Sequel[:resource_paths][:fullpath]

        def parse_paths(path)
            parts = path.split("/")
            leaf  = parts.pop

            [parts.join("/"), leaf]
        end

        def for_path(path)
            resources.where(id:
                resources
                    .select(COL_ID)
                    .join(:resource_paths, id: :id)
                    .where(COL_FULLPATH => path&.chomp("/"))
            )
        end

        def parent_for_path(path)
            parent_path, reqpath = parse_paths(path)

            # special case the top level (it's not an actual collection)
            # returns the ephemeral view, so it's still a dataset
            if parent_path == "" 
                [reqpath, connection[:resource_ephemeral_root]]
            else
                [reqpath, for_path(parent_path)]
            end
        end

    end
end