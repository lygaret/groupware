# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE resources (
          id         TEXT NOT NULL PRIMARY KEY
        , pid        TEXT REFERENCES paths(id) ON DELETE CASCADE

        , type       TEXT
        , length     INTEGER
        , content    BLOB
        , etag       TEXT

        , created_at TEXT
        , updated_at TEXT
      );

      CREATE        INDEX resources_id_idx ON resources(id);
      CREATE UNIQUE INDEX resources_pid_idx ON resources(pid);
    SQL
  end

  down do
    drop_table :resources
  end
end
