require "rack/utils"
require "rack/body_proxy"

module Http
  module Middleware
    class Logger
      def initialize(app, logger)
        @app = app
        @logger = logger
      end

      LogStreamWrapper = Struct.new(:logger) do
        def puts(arg) = logger.unknown arg

        def write(arg) = logger << arg

        def flush # noop
        end
      end

      def call(env)
        env["rack.logger"] = @logger
        env["rack.errors"] = LogStreamWrapper.new @logger

        began_at = Rack::Utils.clock_time
        status, headers, body = @app.call(env)

        [status, headers, Rack::BodyProxy.new(body) { log(env, status, headers, began_at) }]
      end

      private

      FORMAT = %(%s %s%s%s %d %s %0.4f\n)

      def log env, status, headers, began_at
        request = Rack::Request.new(env)
        logger = env["rack.logger"]
        length = headers["Content-Length"].to_i

        logger.unknown do
          sprintf(FORMAT,
            request.request_method,
            request.script_name,
            request.path_info,
            request.query_string.empty? ? "" : "?#{request.query_string}",
            status.to_s[0..3],
            length,
            Rack::Utils.clock_time - began_at)
        end
      end
    end
  end
end
