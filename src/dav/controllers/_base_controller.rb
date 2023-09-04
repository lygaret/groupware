# frozen_string_literal: true

require "rack"

require "dav/_errors"
require "dav/_request"

module Dav
  module Controllers
    class BaseController

      attr_reader :request, :response

      def with_env(env)
        @request  = Dav::Request.new(env)
        @response = Rack::Response.new

        self
      end

      def complete(status)
        response.status = status
        response.finish
      end

      def invalid!(reason = nil, status: 400)
        raise HaltRequest, reason, status:
      end

    end
  end
end
