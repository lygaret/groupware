# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE paths (
          id    TEXT NOT NULL PRIMARY KEY
        , pid   TEXT NULL REFERENCES paths(id) ON DELETE CASCADE

        , path  TEXT NOT NULL  -- the path segment name
        , ctype TEXT NULL      -- controller type
      );

      CREATE        INDEX paths_id_idx      ON paths(id);
      CREATE        INDEX paths_pid_idx     ON paths(pid);
      CREATE UNIQUE INDEX paths_pidpath_idx ON paths(pid, path);

      CREATE VIEW paths_full (id, pid, fullpath, ctype, pctype) AS
        WITH RECURSIVE parents (id, pid, fullpath, ctype, pctype) AS (
          SELECT
              paths.id
            , paths.pid
            , '/' || paths.path
            , paths.ctype
            , coalesce(paths.ctype, 'root')
          FROM paths
          WHERE pid IS NULL
          UNION ALL
          SELECT
              paths.id
            , paths.pid
            , parents.fullpath || '/' || paths.path
            , paths.ctype
            , coalesce(paths.ctype, parents.pctype)
          FROM paths
          INNER JOIN parents ON (paths.pid = parents.id)
        )
        SELECT * FROM parents
    SQL
  end

  down do
    drop_view :paths_full
    drop_table :paths
  end
end
