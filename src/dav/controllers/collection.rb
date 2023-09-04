# frozen_string_literal: true

require "dav/controllers/_base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
    class Collection < BaseController

      include System::Import[
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
        invalid! "path already exists", status: 415 unless path.nil?

        # intermediate collections must already exist
        invalid! "intermediate paths must exist", status: 409 if ppath.nil?

        # we're the root, so no intermediate checking
        paths.insert(pid: ppath[:id], path: request.path.basename, ctype: "collection")
        complete 201 # created
      end

    end
  end
end
