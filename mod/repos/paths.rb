# frozen_string_literal: true

require "repos/base_repo"

module Repos
  # the data access layer to the path storage
  class Paths < BaseRepo

    include System::Import["db.connection"]

    def paths      = connection[:paths]
    def paths_full = connection[:paths_full]

    def resources  = connection[:resources]

    def at_path(path)
      filtered_paths = paths_full.where(fullpath: path)
      paths.join(filtered_paths, id: :id)
    end

    def insert(pid:, path:, ctype: nil)
      paths
        .returning(:id)
        .insert(id: SQL.uuid, pid:, path:, ctype:)
        .then { _1&.first&.[](:id) }
    end

    def delete(id:)
      # cascades in the database to delete children
      paths.where(id:).delete
    end

    def resource_at(pid:) = resources.where(pid:)

    def put_resource(id:, length:, type:, content:, etag:)
      resources
        .returning(:id)
        .insert(id: SQL.uuid, pid: id, length:, type:, content:, etag:)
        .then { _1&.first&.[](:id) }
    end

    # moves the tree at spid now be under dpid, changing it's name
    # simply repoints the spid parent pointer
    def move_tree(id:, dpid:, dpath:)
      paths.where(id:).update(pid: dpid, path: dpath)
    end

    # causes the path tree at spid to be cloned into the path tree at dpid,
    # with the path component dpath;
    #
    # this is a deep clone, including resources at those paths.
    def clone_tree(id:, dpid:, dpath:)
      source_id = paths.literal_append(String.new, Sequel[id])
      dest_pid  = paths.literal_append(String.new, Sequel[dpid])
      dest_path = paths.literal_append(String.new, Sequel[dpath])

      sql = clone_tree_sql.result(binding)
      connection.run sql
    end

    def clone_tree_sql
      @clone_tree_sql ||= begin
        path = File.join(__dir__, "./queries/clone_tree.erb.sql")
        ERB.new(File.read path)
      end
    end

  end
end
