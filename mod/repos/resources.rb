# frozen_string_literal: true

require "repos/base_repo"

module Repos
  # the data access layer to the path storage
  class Resources < BaseRepo

    include System::Import["db.connection"]

    def resources  = connection[:resources]

    def find_by_path(pid:)
      resources.where(pid:)
    end

    def insert(pid:, length:, type:, content:, etag:)
      resources
        .returning(:id)
        .insert(id: SQL.uuid, pid:, length:, type:, content:, etag:)
        .then do |res|
          res&.first&.[](:id)
        end
    end

  end
end
