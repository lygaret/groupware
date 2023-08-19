module Db
    class ResourceRepo
        include App::Import["db.connection"]

        def resources             = connection[:resources]
        def resources_descendants = connection[:resources].join_table(:inner, :resources_closure, id: :id)
        def resources_ancestors   = connection[:resources].join_table(:inner, :resources_closure, root: :id)

        RESOURCES_ID_COL       = Sequel[:resources][:id]
        RESOURCES_TREE_ID_COL  = Sequel[:resources_closure][:id]

        def roots 
            resources_descendants.where(root: 0, depth: 1)
        end

        def ancestors_of(id:)
            resources_ancestors.where(RESOURCES_TREE_ID_COL => id).where{depth>0}.select_all(:resources).select_append('depth')
        end

        def descendants_of(id:)
            resources_descendants.where(root: id).where{depth>0}
        end
    end
end