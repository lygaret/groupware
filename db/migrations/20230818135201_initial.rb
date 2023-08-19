Sequel.migration do
    up do
        create_table :resources, strict: true do
            primary_key :id
            foreign_key :parent_id, :resources, allow_null: true

            text :path
        end

        add_index :resources, :parent_id

        run <<~SQL
            CREATE VIRTUAL TABLE resources_closure 
                USING transitive_closure(tablename='resources', idcolumn='id', parentcolumn='parent_id');
        SQL

        run <<~SQL
            INSERT INTO resources (id, path) VALUES (0, "");
        SQL
    end

    down do
        drop_table :resources_closure;
        drop_table :resources
    end
end