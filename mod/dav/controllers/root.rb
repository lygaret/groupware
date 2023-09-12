# frozen_string_literal: true

require "dav/controllers/collection"

module Dav
  module Controllers
    # collection specific for the root path;
    # only overrides GET in order to allow a response at the root of the tree,
    # it's still not possible to put a resource there (the root is not actually a collection)
    class Root < Collection

      # respond to GET with simple 204
      def get(path:, ppath:)
        complete 204
      end

    end
  end
end
