DROP VIEW IF EXISTS locks_live;
CREATE VIEW locks_live (id, pid, deep, type, scope, owner, timeout, refreshed_at, created_at, expires_at, remaining)
AS
  SELECT
    locks.*,
    (refreshed_at + timeout) as expires_at,
    (refreshed_at + timeout) - unixepoch() as remaining
  FROM locks
  WHERE remaining > 0;
