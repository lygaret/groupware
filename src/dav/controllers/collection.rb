# frozen_string_literal: true

require "dav/controllers/_base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
    class Collection < BaseController

      include System::Import[
        "repos.paths"
      ]

      def get(path:, ppath:)
        [200, {}, ["you got the collection!"]]
      end

      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # intermediate collections must already exist
        invalid! "intermediate paths must exist", status: 409 if ppath.nil?

        # we're the root, so no intermediate checking
        paths.insert(pid: ppath[:id], path: request.path.basename, ctype: "collection")
        complete 201 # created
      end

    end
  end
end
