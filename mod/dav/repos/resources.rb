# frozen_string_literal: true

require "json"
require "nokogiri"

require "dav/ifstate"
require "dav/repos/base_repo"

module Dav
  module Repos
    # the data access layer to the resource storage, used by the default collection controller
    class Resources < BaseRepo

      include System::Import[
        "db.connection",
        "dav.repos.properties",
        "logger"
      ]

      # methods injected into the results hash for the resources table
      module ResourceMethods

        def id   = self[:id]
        def pid  = self[:pid]

        def http_headers
          modtime = self[:updated_at] || resource[:created_at]
          modtime = Time.at(modtime).httpdate

          {
            "Content-Type" => self[:type],
            "Content-Length" => self[:length].to_s,
            "Last-Modified" => modtime,
            "ETag" => self[:etag]
          }
        end

        private

        # hash indexing is made private so as to force the use of getters
        def [](...) = super # rubocop:disable Lint/UselessMethodDefinition

      end

      # simple response body wrapper to return just the contents of a resource
      # rack response bodies must respond to #each or #call
      #
      # TODO: support range reading
      # TODO: support chunked reading/streaming
      ResourceContentBody = Data.define(:resources, :rid) do
        def each
          yield resources.where(id: rid).get(:content)&.to_s
        end
      end

      # @param pid [UUID] the id of the path node to search
      # @return [Hash] the resource row at the given path id, (without content)
      def at_path(pid:)
        cols  = resources.columns.reject { _2 == :content }
        scope = resources.where(pid:).select(*cols)

        scope.first.tap do |v|
          v.singleton_class.include ResourceMethods
        end
      end

      # @return [#each] an iterator over resource content
      def content_for(rid:) = ResourceContentBody.new(resources, rid)

      # clears the resource under the given path
      # @param pid [UUID] the id of the path node to clear
      def clear_at(pid:)
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
      def upsert_at(pid:, display:, type:, lang:, length:, content:, etag:, creating: true)
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
          .then do
            rid = _1.first[:id]
            properties.set_properties(rid:, user: false, props:)
          end
      end

      private

      def resources  = connection[:resources]

    end
  end
end
