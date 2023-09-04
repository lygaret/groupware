# frozen_string_literal: true

require "_utils/md5_reader"
require "dav/controllers/_base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
    class Collection < BaseController

      include System::Import[
        "db.connection",
        "repos.paths",
        "logger"
      ]

      def get(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?

        if path[:ctype]
          # no content for a collection
          complete 204
        else
          # TODO: get resource + header info
          invalid! "not implemented", status: 500
        end
      end

      def head(path:, ppath:)
        status, headers, = get(path:, ppath:)
        [status, headers, []] # just GET but with no body
      end

      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # path itself can't already exist
        invalid! "path already exists", status: 409 unless path.nil?

        # intermediate collections must already exist
        invalid! "intermediate paths must exist", status: 409 if ppath.nil?

        paths.insert(pid: ppath[:id], path: request.path.basename, ctype: "collection")
        complete 201 # created
      end

      def put(path:, ppath:)
        if path.nil?
          put_insert(ppath:)
        else
          put_update(path:, ppath:)
        end
      end

      def delete(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?

        paths.delete(id: path[:id])
        complete 204 # no content
      end

      private

      def put_insert(ppath:)
        invalid! "not found", status: 404 if ppath.nil?
        invalid! "parent must be a collection", status: 409 if ppath[:ctype].nil?

        transaction do
          gpid = ppath[:id]
          path = request.path.basename

          # the new path is the parent of the resource
          pid  = paths.insert(pid: gpid, path:, ctype: nil)

          type          = request.dav_content_type
          length        = request.dav_content_length
          content, etag = read_md5_body(request.body, length)

          # insert the resource at that path
          resources.insert(pid:, length:, type:, content:, etag:)
        end

        complete 201
      end

      def read_md5_body(input, len)
        body = Utils::MD5Reader.new(input)
        data = body.read(len)

        [data, body.hexdigest]
      end

    end
  end
end
