require "rack/utils"
require "rack/body_proxy"

module Http
  class Logger
    def initialize(app, logger)
      @app = app
      @logger = logger
    end

    def call(env)
      env["rack.logger"] = @logger
      began_at = Rack::Utils.clock_time

      status, headers, body = response = @app.call(env)

      response[2] = Rack::BodyProxy.new(body) { log(env, status, headers, began_at) }
      response
    end

    private

    FORMAT = %(%s %s%s%s %d %s %0.4f\n)

    def log env, status, headers, began_at
      request = Rack::Request.new(env)
      length = headers["Content-Length"].to_i

      @logger.info do
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
