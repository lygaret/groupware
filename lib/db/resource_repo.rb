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

    end
end