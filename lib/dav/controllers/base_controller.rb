# frozen_string_literal: true

require "rack"

require "dav/errors"
require "dav/request"

module Dav
  module Controllers
    # Base for DAV resource controllers.
    class BaseController

      attr_reader :request, :response

      # sets this controller up to have easy access to a request/response pair
      # @param {Hash} env the rack environment
      def with_env(env)
        @request  = Dav::Request.new(env)
        @response = Rack::Response.new

        self
      end

      # sets the response status and finishes the response
      # @param status [Integer] the http status code for the response
      # @return [Array] the rack response
      def complete(status)
        response.status = status
        response.finish
      end

      # raises in order to stop request processing in the router
      # @param reason [String] a descriptive reason
      # @param status [Integer] the http status code
      # @raise HaltRequest
      def invalid!(reason = nil, status: 400)
        raise HaltRequest.new(status:), reason
      end

    end
  end
end
