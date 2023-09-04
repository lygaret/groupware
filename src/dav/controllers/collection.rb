# frozen_string_literal: true

require "dav/controllers/_base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
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
