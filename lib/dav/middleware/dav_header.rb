# frozen_string_literal: true

module Dav
  module Middleware
    # Rack middleware to insert the DAV header into responses
    class DavHeader

      # @param app the rack application to wrap
      # @param support [String]
      def initialize(app, support:)
        @app     = app
        @support = support
      end

      def call(env)
        @app.call(env).then do |status, headers, body|
          headers["dav"] = @support

          [status, headers, body]
        end
      end

    end
  end
end
