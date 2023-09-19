# frozen_string_literal: true

require "json"
require "nokogiri"

require "dav/ifstate"
require "dav/repos/base_repo"

module Dav
  module Repos
    # the data access layer to the properties storage
    class Properties < BaseRepo

      include System::Import[
        "db.connection",
        "logger"
      ]

      # get the single named property on the given path
      def find_at_path(pid:, xmlns: "DAV:", xmlel:)
        props = at_path(pid:, depth: 0, filters: [{ xmlns:, xmlel: }])
        props.to_a.first&.[](1)&.first
      end

      # get the single named poperty on the given resource
      def find_at_resource(rid:, xmlns: "DAV:", xmlel:)
        props = at_resource(rid:, depth: 0, filters: [{ xmlns:, xmlel: }])
        props.to_a.first&.[](1)&.first
      end

      # fetch a batch of properties on a path (recursively, up to depth) given a collection of filters.
      # @return [Hash<fullpath, Array<Row>>]
      def at_path(pid:, depth:, filters: nil)
        scopes = [
          # properties of the path
          with_descendents(pid, depth:)
            .join_table(:left_outer, filtered_properties(filters), { pid: :id }, table_alias: :properties)
            .select_all(:properties)
            .select_append(:fullpath),

          # properties of resources _at_ those paths
          with_descendents(pid, depth:)
            .from_self(alias: :paths)
            .join_table(:inner, :resources, { :resources[:pid] => :paths[:id] })
            .join_table(:left_outer, filtered_properties(filters), { rid: :id }, table_alias: :properties)
            .select_all(:properties)
            .select_append(:fullpath)
        ]

        # union all the possible scopes together
        scope = scopes.reduce { |memo, s| memo.union(s) }
        group_by_path(scope)
      end

      # fetch a batch of properties on a resource (by id), given a collection of filters.
      # @return [Hash<fullpath, Array<Row>>]
      def at_resource(rid:, depth:, filters: nil)
        scope = resources
                  .where(id: rid)
                  .join_table(:inner, :paths_extra, { :paths_extra[:id] => :resources[:pid] })
                  .join_table(:left_outer, filtered_properties(filters), { rid: :id }, table_alias: :properties)
                  .select_all(:properties)
                  .select_append(:fullpath)

        group_by_path(scope)
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
            xmlns: prop.namespace&.href || "",
            xmlel: prop.name,
            xmlattrs: prop.attributes.to_a,
            content: prop.children.to_xml
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

      def properties = connection[:properties]

      # returns properties filtered to the given set of property xmlns/xmlel
      def filtered_properties(filters)
        return properties unless filters

        # reduce the filters over `or`, false is the identity there
        initial = properties.where(false)
        filters.reduce(initial) { |scope, filter| scope.or filter }
      end

      # recursive cte to collect fullpath information for descendents of the given pid
      def with_descendents(pid, depth:)
        base_depth = connection[:paths_extra].where(id: pid).get(:depth)

        # NOTE: most of this depends on the structure of the `paths_extra` view
        # and this CTE is just here to be able to select the full descendant tree

        connection[:descendents]
          .with_recursive(
            :descendents,
            connection[:paths_extra]
              .where(id: pid)
              .select_all(:paths_extra),
            connection[:paths_extra]
              .join(:descendents, :paths_extra[:pid] => :descendents[:id])
              .where { :descendents[:depth] < (base_depth + depth) }
              .select_all(:paths_extra),
            args: %i[id pid path fullpath depth ctype pctype lockid plockid lockdeep]
          )
      end

      # group by fullpath; if a property isn't present, add the path to the set anyway
      def group_by_path(scope)
        scope.each_with_object({}) do |row, results|
          results[row[:fullpath]] ||= []
          next if row[:pid].nil? && row[:rid].nil? # nil property from left outer join

          results[row[:fullpath]] << row
        end
      end

    end
  end
end
