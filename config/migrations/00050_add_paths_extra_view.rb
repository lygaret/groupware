# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE VIEW paths_extra (id, pid, path, fullpath, depth, ctype, pctype, lockids, plockids, lockdeeps) AS
        WITH RECURSIVE parents (id, pid, path, fullpath, depth, ctype, pctype, lockid, plockid, lockdeep) AS (
          SELECT
              paths.id
            , paths.pid
            , paths.path
            , '/' || paths.path
            , 0
            , paths.ctype
            , coalesce(paths.ctype, 'root')
            , locks.id
            , locks.id
            , locks.deep
          FROM paths
          LEFT OUTER JOIN locks_live locks ON (locks.pid = paths.id)
          WHERE paths.pid IS NULL
          UNION ALL
          SELECT
              paths.id
            , paths.pid
            , paths.path
            , parents.fullpath || '/' || paths.path
            , parents.depth + 1
            , paths.ctype
            , coalesce(paths.ctype, parents.pctype)
            , locks.id
            , case when (locks.id is null and parents.lockdeep = 1) then parents.lockid else locks.id end
            , case when (locks.id is null and parents.lockdeep = 1) then parents.lockdeep else locks.deep end
          FROM paths
          LEFT OUTER JOIN locks_live locks ON (locks.pid = paths.id)
          INNER JOIN parents ON (paths.pid = parents.id)
        )
        SELECT
            parents.id
          , parents.pid
          , parents.path
          , parents.fullpath
          , parents.depth
          , parents.ctype
          , parents.pctype
          , group_concat(parents.lockid) as lockids
          , group_concat(parents.plockid) as plockids
          , group_concat(parents.lockdeep) as plockdeeps
        FROM parents
        GROUP BY parents.id
    SQL
  end

  down do
    drop_view :paths_extra
  end
end
