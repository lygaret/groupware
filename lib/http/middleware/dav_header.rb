# frozen_string_literal: true

module Http
  module Middleware
    class DavHeader
      def initialize(app, supports:)
        @app      = app
        @supports = supports
      end

      def call(env)
        _, headers,      = response = @app.call(env)
        headers["DAV"] ||= @supports

        response
      end
    end
  end
end
