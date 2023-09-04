# frozen_string_literal: true

require "repos/_base_repo"

module Repos
  # the data access layer to the path storage
  class Paths < BaseRepo

    include System::Import["db.connection"]

    def paths = connection[:paths]

    def at_path(path)
      paths
        .join(:paths_full, id: :id)
        .where(fullpath: path)
    end

    def insert(pid:, path:, ctype: nil)
      results = paths.returning(:id).insert(id: SQL.uuid, pid:, path:, ctype:)
      results&.first&.[](:id)
    end

  end
end
