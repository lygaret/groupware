# frozen_string_literal: true

module Dav
  module Repos
    # Default super class for repositories
    class BaseRepo

      # Sequel helpers, so we don't have to write Sequel so often.
      module SQL

        # sequel function for uuid()
        def self.uuid = Sequel.function(:uuid)

        # sequel function for current timestamp
        def self.now  = Sequel.function(:unixepoch)

        # sequel function: coalesce(...)
        def self.coalesce(...) = Sequel.function(:coalesce, ...)

      end

      # @param data to be converted
      # @return [Sequel::SQL::Blob] the input data converted to a blob
      def blobify(data)
        return data if data.nil?
        return data if data.is_a? Sequel::SQL::Blob

        Sequel::SQL::Blob.new(data)
      end

      # run the block in a transaction under connection
      def transaction(&) = connection.transaction(&)

    end
  end
end
