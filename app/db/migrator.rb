# frozen_string_literal: true

module Db
  class Migrator
    include App::Import["db.connection"]

    def migrations_path
      App::Container.root.join("db/migrations")
    end

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
