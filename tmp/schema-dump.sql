-- 2023/09/11, Migration Level 6

CREATE TABLE `schema_info` (`version` integer DEFAULT (0) NOT NULL);
CREATE TABLE paths (
    id    TEXT NOT NULL PRIMARY KEY
  , pid   TEXT NULL REFERENCES paths(id) ON DELETE CASCADE

  , path  TEXT NOT NULL  -- the path segment name
  , ctype TEXT NULL      -- controller type
);
CREATE INDEX paths_id_idx      ON paths(id);
CREATE INDEX paths_pid_idx     ON paths(pid);
CREATE UNIQUE INDEX paths_pidpath_idx ON paths(pid, path);
CREATE TABLE resources (
    id         TEXT NOT NULL PRIMARY KEY
  , pid        TEXT REFERENCES paths(id) ON DELETE CASCADE

  , type       TEXT
  , lang       TEXT
  , length     INTEGER
  , content    BLOB
  , etag       TEXT

  , created_at INTEGER
  , updated_at INTEGER
);
CREATE INDEX resources_id_idx ON resources(id);
CREATE UNIQUE INDEX resources_pid_idx ON resources(pid);
CREATE TABLE properties (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  pid        TEXT NULL references paths(id) ON DELETE CASCADE,
  rid        TEXT NULL references resources(id) ON DELETE CASCADE,
  user       INTEGER DEFAULT 1, -- true if user property, false if server managed

  xmlns      TEXT NOT NULL, -- the xml namespace owning this property
  xmlel      TEXT NOT NULL, -- the xml element name of this property
  xmlattrs   BLOB NOT NULL, -- the xml attributes, serialized as json array [["attr1","value"], ["attr2","value"]]
  content    BLOB NOT NULL, -- the inner content of the property

  -- we can only have one owner
  CHECK ((pid IS NULL AND rid IS NOT NULL)
      OR (pid IS NOT NULL AND rid IS NULL))
);
CREATE TABLE sqlite_sequence(name,seq);
CREATE INDEX properties_rid_idx on properties (rid);
CREATE UNIQUE INDEX properties_riduserfqn_idx on properties (rid, user, xmlns, xmlel);
CREATE INDEX properties_pid_idx on properties (pid);
CREATE UNIQUE INDEX properties_piduserfqn_idx on properties (pid, user, xmlns, xmlel);
CREATE TABLE locks (
    id           TEXT NOT NULL PRIMARY KEY
  , pid          TEXT REFERENCES paths(id) ON DELETE CASCADE
  , deep         INTEGER NOT NULL DEFAULT 0 -- bool, deep means inherited

  , type         TEXT NOT NULL -- write
  , scope        TEXT NOT NULL -- shared/exclusive
  , owner        TEXT

  , timeout      INTEGER       -- seconds to hold lock open
  , refreshed_at INTEGER       -- last submitted timestamp
  , created_at   INTEGER       -- when originally opened
);
CREATE INDEX locks_pid_idx          ON locks(pid);
CREATE INDEX locks_submitted_ts_idx ON locks(refreshed_at + timeout);
CREATE VIEW locks_live (id, pid, deep, type, scope, owner, timeout, refreshed_at, created_at, expires_at, remaining)
AS
  SELECT
    locks.*,
    (refreshed_at + timeout) as expires_at,
    (refreshed_at + timeout) - unixepoch() as remaining
  FROM locks
  WHERE remaining > 0
/* locks_live(id,pid,deep,type,scope,owner,timeout,refreshed_at,created_at,expires_at,remaining) */;
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
/* paths_extra(id,pid,path,fullpath,depth,ctype,pctype,lockids,plockids,lockdeeps) */;
