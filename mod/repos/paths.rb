# frozen_string_literal: true

require "repos/base_repo"

module Repos
  # the data access layer to the path storage
  class Paths < BaseRepo

    include System::Import["db.connection"]

    def paths      = connection[:paths]
    def paths_full = connection[:paths_full]

    def at_path(path)
      filtered_paths = paths_full.where(fullpath: path)
      paths.join(filtered_paths, id: :id)
    end

    def insert(pid:, path:, ctype: nil)
      results = paths.returning(:id).insert(id: SQL.uuid, pid:, path:, ctype:)
      results&.first&.[](:id)
    end

    def delete(id:)
      # cascades in the database to delete children
      paths.where(id:).delete
    end

  end
end
