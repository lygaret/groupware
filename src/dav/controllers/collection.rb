require 'dav/controllers/_base_controller'

module Dav
  module Controllers

    class Collection < BaseController

      include System::Import[
        "repos.paths"
      ]

      def get(path:, ppath:, env:)
        [200, {}, ["you got the collection!"]]
      end

    end

  end
end
