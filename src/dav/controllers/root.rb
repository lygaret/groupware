# frozen_string_literal: true

require "rack/constants"
require "dav/controllers/_base_controller"

module Dav
  module Controllers
    # controller for resources when the path is empty.
    class Root < BaseController

      include System::Import[
        "repos.paths"
      ]

      def get(path:, ppath:)
        [200, {}, ["you got the root"]]
      end

      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # we're the root, so no intermediate checking
        paths.insert(pid: nil, path: request.path.basename, ctype: "collection")
        complete 201 # created
      end

    end
  end
end
