# frozen_string_literal: true

require "utils/base_58"

module Dav
  module Middleware
    # simple middleware to inject a random request id which can be used for logging
    class RequestId

      def initialize(app)
        @app = app
      end

      def call(env)
        id                      = (env["HTTP_X_REQUEST_ID"] = Utils::Base58.random_base58(8))
        status, headers, body   = @app.call(env)
        headers["x-request-id"] = id
        [status, headers, body]
      end

    end
  end
end
