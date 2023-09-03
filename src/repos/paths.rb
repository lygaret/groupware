require_relative "./_base_repo"

module Repos
  class Paths < BaseRepo

    include System::Import["db.connection"]

    def paths = connection[:paths]

    def at(path, depth: 0)
      paths
        .join(:paths_closure, root: )
    end

    def insert pid:, path:, ctype: nil
      results = paths.returning(:id).insert(id: SQL.uuid, pid:, path:, ctype:)
      results&.first[:id]
    end

  end
end
