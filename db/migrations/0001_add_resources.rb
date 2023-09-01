# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      -- the tree structure of the nodes

      CREATE TABLE resources (
          id       TEXT NOT NULL PRIMARY KEY,
          pid      TEXT NULL REFERENCES resources(id) ON DELETE CASCADE,

          path     TEXT NOT NULL,              -- the path segment name
          colltype TEXT NULL, -- is collection?

          type     TEXT,
          length   INTEGER,
          content  BLOB,

          etag       TEXT,
          created_at TEXT,
          updated_at TEXT
      );

      CREATE        INDEX resources_id_idx      ON resources(id);
      CREATE        INDEX resources_pid_idx     ON resources(pid);
      CREATE UNIQUE INDEX resources_pidpath_idx ON resources(pid, path);

      -- view which represents the materialized paths along the tree
      -- used to search the tree for a given path/depth

      CREATE VIEW resource_paths (id, depth, path, colltype) AS
          WITH RECURSIVE paths(id, depth, path, colltype) AS (
              SELECT r.id, 0, '/' || r.path, r.colltype
              FROM   resources r
              WHERE  r.pid IS NULL -- root nodes
                  UNION
              SELECT r.id, p.depth + 1, p.path || '/' || r.path, coalesce(r.colltype, p.colltype)
              FROM   resources r, paths p
              WHERE  r.pid = p.id  -- top-down traversal
          )
          SELECT id, depth, path, colltype FROM paths;

      -- view which can be selected against to represent the empty root
      -- used to allow querying the "parent" of a node without special casing

      CREATE VIEW resource_ephemeral_root (id, pid, path, colltype) AS
          WITH ephemeral_root(id, pid, path, colltype) AS (
              VALUES(NULL, NULL, '', 'root')
          )
          SELECT * from ephemeral_root;
    SQL
  end

  down do
    drop_view :resource_paths
    drop_view :resource_ephemeral_root
    drop_table :resources
  end
end
