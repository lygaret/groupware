# frozen_string_literal: true

module Repos
  # Default super class for repositories
  class BaseRepo

    # Sequel helpers, so we don't have to write Sequel so often.
    module SQL

      def self.uuid = Sequel.function(:uuid)
      def self.now  = Sequel.function(:datetime, "now")

      def self.like(...)  = Sequel.like(...)
      def self.ilike(...) = Sequel.ilike(...)

      def self.coalesce(...) = Sequel.function(:coalesce, ...)

    end

    def blobify(data)
      return data if data.nil?
      return data if data.is_a? Sequel::SQL::Blob

      Sequel::SQL::Blob.new(data)
    end

    def transaction(&) = connection.transaction(&)

  end
end
