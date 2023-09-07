# frozen_string_literal: true

require "json"
require "nokogiri"

require "repos/base_repo"

module Repos
  # the data access layer to the path storage
  class Paths < BaseRepo

    include System::Import["db.connection"]

    # @param fullpath [String] the full path to find (eg. "/some/full/path")
    # @return [Hash] the path row at the given full path
    def at_path(fullpath)
      filtered_paths = paths_full.where(fullpath:)
      paths.join(filtered_paths, id: :id).first
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

    # @param pid [UUID] the id of the path node to search
    # @return [Hash] the resource row at the given path id
    def resource_at(pid:) = resources.where(pid:).first

    # clears the resource under the given path
    # @param pid [UUID] the id of the path node to clear
    def clear_resource(pid:)
      resources.where(pid:).delete
    end

    # put a resource under a given path
    # @param pid [UUID] the id path of the path node to insert under
    # @param display [String] the display name of the resource
    # @param type [String] the mimetype of the resource
    # @param lang [String] the content language of the resource
    # @param content [String] the resource content to store -- this is blobified before saving
    # @param etag [String] the resource's calculated etag
    # @param creating [Bool] when true, the creation date is managed on the resource
    def put_resource(pid:, display:, type:, lang:, length:, content:, etag:, creating: true)
      content    = blobify(content)
      updated_at = Time.now.utc

      values  = { id: SQL.uuid, pid:, type:, lang:, length:, content:, etag:, updated_at: }
      props   = [
        { xmlel: "displayname",        content: display },
        { xmlel: "getcontentlanguage", content: lang },
        { xmlel: "getcontentlength",   content: length },
        { xmlel: "getcontenttype",     content: type },
        { xmlel: "getetag",            content: etag },
        { xmlel: "getlastmodified",    content: updated_at }
      ]

      if creating
        created_at = Time.now.utc

        props << { xmlel: "creationdate", content: created_at }
        values[:created_at] = created_at
      end

      resources
        .returning(:id)
        .insert_conflict(:replace)
        .insert(**values)
        .then { _1.first[:id] }
        .then { set_properties(rid: _1, user: false, props:) }
    end

    # fetch a batch of properties on either a path (recursively, up to depth) or a resource (by id),
    # given a collection of filters.
    #
    # @return [Hash<fullpath, Array<Row>>]
    def properties_at(pid: nil, rid: nil, depth:, filters: nil)
      raise ArgumentError, "only one of pid or rid may be specified!" if pid && rid
      raise ArgumentError, "one of pid or rid must be specified!" unless pid || rid

      scopes = []
      unless pid.nil?
        # properties both of the path _and_ the resource _at_ that path
        scopes << with_descendents(pid, depth:)
                    .join_table(:left_outer, filtered_properties(filters), { pid: :id }, table_alias: :properties)
                    .select_all(:properties)
                    .select_append(:fullpath)

        scopes << with_descendents(pid, depth:)
                    .from_self(alias: :paths)
                    .join_table(:inner, :resources, { :resources[:pid] => :paths[:id] })
                    .join_table(:left_outer, filtered_properties(filters), { rid: :id }, table_alias: :properties)
                    .select_all(:properties)
                    .select_append(:fullpath)
      else
        # properties just of resource
        scopes << resources
                    .where(id: rid)
                    .join_table(:inner, :paths_full, { :paths_full[:id] => resources[:pid] })
                    .join_table(:left_outer, filtered_properties(filters), { rid: :id }, table_alias: :properties)
                    .select_all(:properties)
                    .select_append(:fullpath)
      end

      # union all the possible scopes together
      scope = scopes.reduce { |memo, s| memo.union(s) }

      # and then group by fullpath
      scope.each_with_object({}) do |row, results|
        results[row[:fullpath]] ||= []
        next if row[:pid].nil? && row[:rid].nil? # nil object from left outer join

        results[row[:fullpath]] << row
      end
    end

    # set a batch of properties on either a path or a resource (by id), given a collection of
    # property definitions containing keys:
    #
    # * `xmlns:`    - defaults to `"DAV:"`
    # * `xmlel:`    - required, no default
    # * `xmlattrs:` - default to an empty hash
    # * `content:`  - default to an empty string, parsed into an xml fragment
    #
    # @example
    #   props = [
    #     { xmlel: "foo" },
    #        # equiv: <foo xmlns="DAV:"/>
    #     { xmlel: "bar", content: "hello" },
    #        # equiv: <bar xmlns="DAV:">hello</bar>
    #     { xmlns: "urn:blah", xmlel: "baz", xmlattrs: { zip: "zap" }, content: "<kablam>pow</kablam>" }
    #        # equiv: <baz xmlns="urn:blah" zip="zap"><kablam>pow</kablam></pow>
    #        # note that kablam is implicitly in the same namespace as baz
    #   ]
    #
    #   set_properties(pid:, user: true, props:)
    #
    # @param pid
    def set_properties(pid: nil, rid: nil, user:, props:)
      props = props.map do |prop|
        [
          pid, rid, user,
          prop.fetch(:xmlns, "DAV:"),
          prop[:xmlel] || (raise ArgumentError, "missing xmlel column"),
          prop.fetch(:xmlattrs, {}).then { JSON.dump(_1.to_a) },
          prop.fetch(:content, "").then { Nokogiri::XML.fragment(_1).to_xml }
        ]
      end

      connection[:properties]
        .insert_conflict(:replace)
        .import(%i[pid rid user xmlns xmlel xmlattrs content], props)
    end

    # set a batch of properties on either a path or a resource (by id), given xml nodes# (eg. from `<set>`)
    # only one of `pid` or `rid` should be non-nil; the query will fail if both are present.
    #
    # any property already present by `(user,xmlns,xmlel)` will be overwritten.
    #
    # @param pid [UUID] the id of the path node to set the property on
    # @param rid [Integer] the id of the resource to set the property on
    # @param user [Bool] true if the property is being set on behalf of the user, false if it's system managed
    # @param props [Array<Nokogiri::Element>] a child of `<prop>` element
    # @see https://www.rfc-editor.org/rfc/rfc4918.html#section-14.18
    def set_xml_properties(pid: nil, rid: nil, user:, props:)
      props = props.map do |prop|
        {
          xmlns:    prop.namespace&.href || "",
          xmlel:    prop.name,
          xmlattrs: prop.attributes.to_a,
          content:  prop.children.to_xml
        }
      end

      set_properties(pid:, rid:, user:, props:)
    end

    # clear a batch of properties on either a path or a resource (by id), given a collection of filters
    #
    # @param pid [UUID] the id of the path node to set the property on
    # @param rid [Integer] the id of the resource to set the property on
    # @param user [Bool] true if the property is set on behalf of the user, false if it's system managed
    # @param filters [Array<Hash>] list of `{ xmlns:, xmlel: }` filters for removal
    def remove_properties(pid: nil, rid: nil, user:, filters:)
      filters = filters.map { _1.slice(:xmlns, :xmlel) }

      query = connection[:properties].where(false)
      query = filters.reduce(query) do |scope, filter|
        scope.or(pid:, rid:, user:, **filter)
      end

      query.delete
    end

    # clear a batch of properties on either a path or a resource (by id), given xml nodes (eg. from `<remove>`)
    #
    # @param pid [UUID] the id of the path node to set the property on
    # @param rid [Integer] the id of the resource to set the property on
    # @param user [Bool] true if the property is set on behalf of the user, false if it's system managed
    # @param props [Array<Nokogiri::Element>] a child of `<prop>` element
    # @see https://www.rfc-editor.org/rfc/rfc4918.html#section-14.18
    def remove_xml_properties(pid: nil, rid: nil, user:, props:)
      filters = props.map do |prop|
        {
          xmlns: prop.namespace&.href || "",
          xmlel: prop.name
        }
      end

      remove_properties(pid:, rid:, user:, filters:)
    end

    private

    def paths      = connection[:paths]
    def paths_full = connection[:paths_full]

    def resources  = connection[:resources]
    def properties = connection[:properties]

    def clone_tree_sql
      @clone_tree_sql ||= File.read File.join(__dir__, "./queries/clone_tree.sql")
    end

    # returns properties filtered to the given set of property xmlns/xmlel
    def filtered_properties(filters)
      if filters
        # reduce the filters over `or`, false is the identity there
        initial = properties.where(false)
        filters.reduce(initial) { |scope, filter| scope.or filter }
      else
        connection[:properties]
      end
    end

    # recursive cte to collect fullpath information for descendants of the given pid
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

  end
end
