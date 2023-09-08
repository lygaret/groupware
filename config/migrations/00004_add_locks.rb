# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE locks (
          id           TEXT NOT NULL PRIMARY KEY
        , pid          TEXT REFERENCES paths(id) ON DELETE CASCADE
        , depth        INTEGER NOT NULL

        , type         TEXT NOT NULL    -- write
        , exclusive    INTEGER NOT NULL -- shared/exclusive

        , timeout      INTEGER          -- seconds to hold lock open
        , refreshed_at INTEGER          -- last submitted timestamp
        , created_at   INTEGER          -- when originally opened
      );

      CREATE UNIQUE INDEX locks_pid_idx          ON locks(pid);
      CREATE        INDEX locks_submitted_ts_idx ON locks(refreshed_at + timeout);

      CREATE VIEW locks_live (id, pid, depth, type, exclusive, timeout, refreshed_at, created_at, expires_at) AS
        SELECT locks.*, refreshed_at + timeout as expires_at
        FROM locks WHERE (refreshed_at + timeout) > unixepoch();
    SQL
  end

  down do
    drop_view :locks_live
    drop_table :locks
  end
end
