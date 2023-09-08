# frozen_string_literal: true

require "securerandom"

module Dav
  module Middleware
    # simple middleware to inject a random request id which can be used for logging
    class RequestId

      def initialize(app)
        @app = app
      end

      def call(env)
        id                      = (env["HTTP_X_REQUEST_ID"] = SecureRandom.urlsafe_base64)
        status, headers, body   = @app.call(env)
        headers["x-request-id"] = id
        [status, headers, body]
      end

    end
  end
end
