# frozen_string_literal: true

require "json"
require "nokogiri"

require "dav/ifstate"
require "dav/repos/base_repo"

module Dav
  module Repos
    # the data access layer to the path storage
    class Paths < BaseRepo

      include System::Import[
        "db.connection",
        "logger"
      ]

      # methods injected into result hashes for the paths table
      module PathMethods

        def id          = self[:id]
        def path        = self[:path]

        def lockids     = self[:lockids]&.split(",")&.map { LockId.new _1 }
        def plockids    = self[:plockids]&.split(",")&.map { LockId.new _1 }

        def collection?    = !self[:ctype].nil?
        def controller_key = "dav.controllers.#{self[:pctype]}"

        private

        # hash indexing is made private so as to force the use of getters
        def [](...) = super # rubocop:disable Lint/UselessMethodDefinition

      end

      # data wrapper for lock ids, which can parse and generate tokens
      LockId = Data.define(:lid) do
        def self.from_token(token)
          return token if token.is_a? LockId

          match = token.match(/urn:x-groupware:(?<lid>[^?]+)\?=lock/i)
          match && new(match[:lid])
        end

        def self.from_lid(lid)
          lid.is_a?(LockId) ? lid : new(lid)
        end

        def token = "urn:x-groupware:#{lid}?=lock"
      end

      # @param fullpath [String] the full path to find (eg. "/some/full/path")
      # @return [Hash] the path row at the given full path
      def at_path(fullpath)
        fullpath = fullpath.chomp("/") # normalize for collections
        return nil if fullpath == ""

        filtered_paths = connection[:paths_extra].where(fullpath:)
        paths
          .join(filtered_paths, { id: :id }, table_alias: :extra)
          .select_all(:paths)
          .select_append(
            :extra[:fullpath],
            :extra[:pctype],
            :extra[:lockids],
            :extra[:plockids],
            :extra[:lockdeeps]
          )
          .first
          .tap do |v|
            v.singleton_class.include PathMethods
          end
      end

      # insert a new path node
      # @param pid [UUID] the id of the path component to insert underneath
      # @param path [String] the subpath to create
      # @param ctype [String] the type of path node to create
      # @return [UUID] the new id of the path created
      def insert(pid:, path:, ctype: nil)
        paths
          .returning(:id)
          .insert(id: SQL.uuid, pid:, path:, ctype:)
          .then { _1&.first&.[](:id) }
      end

      # recursively deletes the path, along with resources and properties
      # @param id [UUID] the id of the path to delete
      def delete(id:)
        # cascades in the database to delete children
        paths.where(id:).delete
      end

      # moves the tree at spid now be under dpid, changing it's name
      # @note O(1) time - simply repoints the spid parent pointer
      # @param id [UUID] the id of the path node representing the subtree to move
      # @param dpid [UUID] the id of the destination parent node
      # @param dpath [String] the new path under the parent node
      def move_tree(id:, dpid:, dpath:)
        paths.where(id:).update(pid: dpid, path: dpath)
      end

      # clones the tree at spid under dpid; this is a deep clone, including properties
      # and resources at those paths.
      # @note O(n^m) time, because we recurse through resources and properties at least
      # @param id [UUID] the id of the path node representing the subtree to move
      # @param dpid [UUID] the id of the destination parent node
      # @param dpath [String] the new path under the parent node
      def clone_tree(id:, dpid:, dpath:)
        ds = connection[clone_tree_sql, id:, dpid:, dpath:]
        connection.run ds.select_sql
      end

      # insert a lock on the given pid
      def grant_lock(pid:, deep:, type:, scope:, owner:, timeout:)
        now = Time.now.utc.to_i
        locks
          .returning(:id)
          .insert(id: SQL.uuid, pid:, deep:, type:, scope:, owner:, timeout:, refreshed_at: now, created_at: now)
          .then { LockId.new(_1.first[:id]) }
      end

      # refresh the lock at the token
      def refresh_lock(token:, timeout:)
        id  = LockId.from_token(token)
        now = Time.now.utc.to_i

        id && locks.where(id: id.lid).update(timeout:, refreshed_at: now)
      end

      # pull the lock given the given token
      def lock_info(token:)
        id = LockId.from_token(token)
        return nil if id.nil?

        info = locks_live.where(id: id.lid).first
        return nil if info.nil?

        info.merge(id:)
      end

      # @param extant [Array<LockId>] the lockids to check
      # @param scope ["exclusive", "shared"] the scope of the new lock
      # @return [bool] whether or not the given extant locks preclude a new lock with the given scope
      def lock_allowed?(lids:, scope:)
        return true if lids.nil? || lids.empty?

        # pull the actual locks by id
        extantids = lids.map { LockId.from_lid _1 }.map(&:lid)
        extants   = locks_live.where(id: extantids).select(:scope).all

        # no extant live locks, no big deal
        return true if extants.empty?

        # asking for an exclusive lock fails if there are other locks
        return false if scope == "exclusive"

        # asking for a shared lock fails if any of the extant locks are exclusive
        extants.none? { _1[:scope] == "exclusive" }
      end

      # remove the lock for the given token
      def clear_lock(token:)
        id = LockId.from_token(token)
        id && locks.where(id: id.lid).delete
      end

      private

      def paths      = connection[:paths]

      def clone_tree_sql
        @clone_tree_sql ||= File.read File.join(__dir__, "./queries/clone_tree.sql")
      end

      def locks      = connection[:locks]
      def locks_live = connection[:locks_live]

      def toggle_bool(bool, toggle) = toggle ? !bool : bool

    end
  end
end
