# frozen_string_literal: true

require "json"
require "nokogiri"

require "repos/base_repo"

module Repos
  # the data access layer to the path storage
  class Paths < BaseRepo

    include System::Import["db.connection"]

    def paths      = connection[:paths]
    def paths_full = connection[:paths_full]

    def resources  = connection[:resources]
    def properties = connection[:properties]

    def at_path(path)
      filtered_paths = paths_full.where(fullpath: path)
      paths.join(filtered_paths, id: :id).first
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

    def resource_at(pid:) = resources.where(pid:).first

    def clear_resource(pid:)
      resources.where(pid:).delete
    end

    def put_resource(pid:, length:, type:, content:, etag:)
      resources
        .returning(:id)
        .insert(id: SQL.uuid, pid:, length:, type:, content:, etag:)
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
        ERB.new(File.read(path))
      end
    end

    def set_property(pid: nil, rid: nil, user: true, prop:)
      xmlns    = prop.namespace&.href || ""
      xmlel    = prop.name
      xmlattrs = JSON.dump prop.attributes.to_a
      content  = Nokogiri::XML.fragment(prop.children).to_xml

      connection[:properties]
        .insert_conflict(:replace)
        .insert(pid:, rid:, user:, xmlns:, xmlel:, xmlattrs:, content:)
    end

    def set_explicit_property(pid: nil, rid: nil, user:, xmlns: "DAV:", xmlel:, xmlattrs: {}, content:)
      content  = Nokogiri::XML.fragment(content).to_xml
      xmlattrs = JSON.dump xmlattrs.to_a

      connection[:properties]
        .insert_conflict(:replace)
        .insert(pid:, rid:, user:, xmlns:, xmlel:, xmlattrs:, content:)
    end

    def clear_property(pid: nil, rid: nil, user: true, xmlns:, xmlel:)
      connection[:properties]
        .where(pid:, rid:, user:, xmlns:, xmlel:)
        .delete
    end

    def with_descendents(pid, depth:)
      connection[:descendents]
        .with_recursive(
          :descendents,
          connection[:paths_full]
            .where(id: pid)
            .select(:id, :fullpath, Sequel[0].as(:depth), :ctype, :pctype),
          connection[:paths_full]
            .join(:descendents, id: :pid)
            .where { :descendents[:depth] < depth }
            .select(:paths_full[:id])
            .select_append(:paths_full[:fullpath])
            .select_append(:descendents[:depth] + 1)
            .select_append(:paths_full[:ctype])
            .select_append(:paths_full[:pctype]),
          args: %i[id fullpath depth ctype pctype]
        )
    end

    def properties_at(pid: nil, rid: nil, depth:, filters: nil)
      scopes = []

      unless pid.nil?
        scopes << with_descendents(pid, depth:)
                    .join_table(:left_outer, filtered_properties(filters), { pid: :id }, table_alias: :properties)
                    .select_all(:properties)
                    .select_append(:fullpath)

        scopes << with_descendents(pid, depth:)
                    .from_self(alias: :paths)
                    .join_table(:inner, :resources,       { :resources[:pid] => :paths[:id] })
                    .join_table(:left_outer, :properties, { :properties[:rid] => :resources[:id] })
                    .select_all(:properties)
                    .select_append(:fullpath)
      end

      unless rid.nil?
        scopes << resources
                    .where(id: rid)
                    .join_table(:inner, :paths_full, { :paths_full[:id] => resources[:pid] })
                    .join_table(:left_outer, :properties, { :properties[:rid] => :resources[:id] })
                    .select_all(:properties)
                    .select_append(:fullpath)
      end

      scope = scopes.reduce { |memo, s| memo.union(s) }
      # debugger

      scope.each_with_object({}) do |row, results|
        results[row[:fullpath]] ||= []
        next if row[:pid].nil? && row[:rid].nil? # nil object from left outer join

        results[row[:fullpath]] << row
      end
    end

    def blobify_data_content(data)
      return data unless data.key? :content
      return data if data[:content].nil?

      data.merge(content: Sequel::SQL::Blob.new(data[:content]))
    end

    # returns properties_all, filtered to the given set of property xmlns/xmlel
    def filtered_properties(filters)
      if filters
        # reduce the filters over `or`, false is the identity there
        initial = properties.where(false)
        filters.reduce(initial) { |scope, filter| scope.or filter }
      else
        connection[:properties]
      end
    end

  end
end
