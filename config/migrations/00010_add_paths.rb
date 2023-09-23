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
    SQL

    run_file "./views/paths_full_01.sql"
  end

  down do
    drop_view :paths_full
    drop_table :paths
  end
end
