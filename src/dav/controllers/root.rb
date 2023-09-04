# frozen_string_literal: true

require "dav/controllers/_base_controller"

module Dav
  module Controllers
    # controller for resources when the path is empty.
    class Root < BaseController

      include System::Import[
        "repos.paths"
      ]

      def get(path:, ppath:, env:)
        [200, {}, ["you got the root"]]
      end

      def mkcol(path:, ppath:, env:)
        request  = Rack::Request.new(env)
        pathname = Dav::Pathname.parse request.path_info

        paths.insert(pid: nil, path: pathname.basename, ctype: "collection")
        [204, {}, []]
      end

    end
  end
end
