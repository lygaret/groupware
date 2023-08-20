Sequel.migration do
    up do
        run <<~SQL
            CREATE TABLE resources (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                pid     INTEGER NULL REFERENCES resources(id),
                path    TEXT NOT NULL,
                is_coll INTEGER NOT NULL DEFAULT 0,
                content BLOB,
                mime    TEXT
            );

            CREATE INDEX resources_pid_idx ON resources(pid);

            CREATE VIEW resource_paths (id, fullpath) AS
                WITH RECURSIVE _paths(id, fullpath) AS (
                    SELECT resources.id, '/' || resources.path 
                    FROM   resources
                    WHERE  resources.pid IS NULL
                    UNION
                    SELECT resources.id, _paths.fullpath || '/' || resources.path
                    FROM   resources, _paths
                    WHERE  resources.pid = _paths.id
                )
                SELECT id, fullpath FROM _paths;
        SQL
    end

    down do
        drop_view  :resource_paths
        drop_table :resources
    end
end