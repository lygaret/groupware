-- DEPRECATED DONT USE!

DROP VIEW IF EXISTS paths_full;
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
  SELECT * FROM parents;
