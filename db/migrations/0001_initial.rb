Sequel.migration do
    up do
        run <<~SQL
            CREATE TABLE resources (
                id      INTEGER PRIMARY KEY AUTOINCREMENT,
                pid     INTEGER NULL REFERENCES resources(id) ON DELETE CASCADE,
                path    TEXT NOT NULL,
                is_coll INTEGER NOT NULL DEFAULT 0,
                content BLOB,
                mime    TEXT
            );

            CREATE INDEX resources_pid_idx ON resources(pid);

            CREATE VIEW resource_paths (id, depth, fullpath) AS
                WITH RECURSIVE _paths(id, depth, fullpath) AS (
                    SELECT resources.id, 0, '/' || resources.path
                    FROM   resources
                    WHERE  resources.pid IS NULL
                    UNION
                    SELECT resources.id, _paths.depth + 1, _paths.fullpath || '/' || resources.path
                    FROM   resources, _paths
                    WHERE  resources.pid = _paths.id
                )
                SELECT id, depth, fullpath FROM _paths;

            CREATE VIEW resource_ephemeral_root (id, pid, path, is_coll, content, mime) AS
                WITH _root(id, pid, path, is_coll, content, mime) AS (
                    VALUES(NULL, NULL, '', TRUE, NULL, NULL)
                )
                SELECT * from _root;
        SQL
    end

    down do
        drop_view  :resource_paths
        drop_table :resources
    end
end