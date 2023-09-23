# frozen_string_literal: true

# https://sequel.jeremyevans.net/
module Sequel

  # @example
  #   Sequel.sqlfile_roots << System::Container.root.join "queries"
  #   Sequel.sqlfile_roots << System::Container.root.join "views"
  #
  # @return [Array<paths>] the list of directories to search for files in {run_file}
  def self.sqlfile_roots
    @sqlfile_roots ||= []
  end

  module Extensions
    # small sequel extension to allow running SQL from files
    module SqlFile

      # run the first file found with the given relative path in {Sequel.sqlfile_roots}
      def run_file(path)
        paths = Sequel.sqlfile_roots.map { File.expand_path(path, _1) }
        realp = paths.find { File.exist? _1 }
        raise ArgumentError, "nothing at path: #{path}!" unless realp

        sql = File.read(realp)
        run sql
      end

    end
  end

  Database.register_extension(:sqlfile, Extensions::SqlFile)

end
