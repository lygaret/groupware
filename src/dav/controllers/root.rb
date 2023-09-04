# frozen_string_literal: true

require "rack/constants"
require "dav/controllers/collection"

module Dav
  module Controllers
    # controller for resources when the path is empty.
    class Root < Collection

      # no content
      def get(path:, ppath:)  = complete 204
      def head(path:, ppath:) = complete 204

      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # path itself can't already exist
        # but we're the root, so no intermediate checking
        invalid! "path already exists", status: 415 unless path.nil?

        paths.insert(pid: nil, path: request.path.basename, ctype: "collection")
        complete 201 # created
      end

    end
  end
end
