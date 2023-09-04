# frozen_string_literal: true

require "rack"

require "dav/_errors"
require "dav/_request"

module Dav
  module Controllers
    # Base for DAV resource controllers.
    class BaseController

      attr_reader :request, :response

      def with_env(env)
        @request  = Dav::Request.new(env)
        @response = Rack::Response.new

        self
      end

      def transaction(&)
        connection.transaction(&)
      end

      def complete(status)
        response.status = status
        response.finish
      end

      def invalid!(reason = nil, status: 400)
        raise HaltRequest.new(status:), reason
      end

    end
  end
end
