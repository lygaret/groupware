Sequel.migration do
    up do
        add_column :resources, :full_path, :text, null: true
        run <<~SQL
            CREATE TRIGGER resources_full_path_insert
            AFTER INSERT ON resources 
            BEGIN
                UPDATE resources
                SET full_path = (
                    SELECT group_concat(resources.path, "/")
                    FROM resources INNER JOIN resources_closure ON (resources_closure.root = resources.id)
                    WHERE resources_closure.id = new.id
                )
                WHERE id = new.id;
            END;

            CREATE TRIGGER resources_full_path_update
            AFTER UPDATE ON resources 
            WHEN new.path <> old.path OR new.full_path IS NULL
            BEGIN
                UPDATE resources
                SET full_path = (
                    SELECT group_concat(resources.path, "/")
                    FROM resources INNER JOIN resources_closure ON (resources_closure.root = resources.id)
                    WHERE resources_closure.id = new.id
                )
                WHERE id = new.id;
            END;
        SQL
    end

    down do
        drop_column :resources, :full_path
        run <<~SQL
            DROP TRIGGER IF EXISTS resources_full_path_insert;
            DROP TRIGGER IF EXISTS resources_full_path_update;
        SQL
    end
end