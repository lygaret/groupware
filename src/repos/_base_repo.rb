# frozen_string_literal: true

module Repos
  class BaseRepo
    # Sequel helpers, so we don't have to write Sequel so often.
    module SQL

      def self.uuid = Sequel.function(:uuid)
      def self.now  = Sequel.function(:datetime, "now")

    end
  end
end
