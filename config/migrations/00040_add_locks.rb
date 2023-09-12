# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
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

      -- should be a unique, but it's hard to guarantee
      CREATE INDEX locks_pid_idx          ON locks(pid);
      CREATE INDEX locks_submitted_ts_idx ON locks(refreshed_at + timeout);

      CREATE VIEW locks_live (id, pid, deep, type, scope, owner, timeout, refreshed_at, created_at, expires_at, remaining)
      AS
        SELECT
          locks.*,
          (refreshed_at + timeout) as expires_at,
          (refreshed_at + timeout) - unixepoch() as remaining
        FROM locks
        WHERE remaining > 0;
    SQL
  end

  down do
    drop_view :locks_live
    drop_table :locks
  end
end
