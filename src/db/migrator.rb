# frozen_string_literal: true

module Db
  # command to run migrations.
  #
  # @note because we customize our database connection, we need to
  #       provide an explicit connection to the migrator, making
  #       `sequel migrate` inappropriate.
  class Migrator
    include System::Import["db.connection"]

    def migrations_path = File.expand_path("./_migrations", __dir__)

    def check!
      Sequel.extension :migration
      Sequel::Migrator.check_current(connection, migrations_path)
    end

    def run!(version: nil)
      Sequel.extension :migration
      Sequel::Migrator.run(connection, migrations_path, target: version)
    end
  end
end
