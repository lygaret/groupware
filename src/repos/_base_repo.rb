module Repos
  class BaseRepo

    module SQL

      def self.uuid = Sequel.function(:uuid)
      def self.now  = Sequel.function(:datetime, "now")

    end

  end
end
