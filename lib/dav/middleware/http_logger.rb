# frozen_string_literal: true

require "rack"
require "rack/utils"

module Dav
  module Middleware
    # HttpLogger logs http methods to the given logger and level
    class HttpLogger

      def initialize(app, logger:, level:)
        @app    = app
        @logger = logger
        @level  = logger.from_label level.to_s.upcase
      end

      # log requests before and after the response has been returned
      def call(env)
        began_at = Rack::Utils.clock_time
        request  = Rack::Request.new(env)

        data = {
          req_id: env["HTTP_X_REQUEST_ID"],
          method: request.request_method,
          path_info: request.path_info,
          query_string: request.query_string.empty? ? "" : "?#{request.query_string}"
        }

        begin
          status, headers, body = response = @app.call(env)
          response[2]           = Rack::BodyProxy.new(body) do
            duration = (Rack::Utils.clock_time - began_at).round(7)
            length   = content_length headers
            @logger.log(@level, data.merge(status:, length:, duration:))
          end
          response
        rescue StandardError => e
          duration = Rack::Utils.clock_time - began_at
          @logger.error(e, data.merge(status: 500, duration:))

          raise
        end
      end

      private

      def content_length(headers)
        value = headers[Rack::CONTENT_LENGTH]
        !value || value.to_s == "0" ? "-" : value
      end

    end
  end
end
