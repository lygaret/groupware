# frozen_string_literal: true

require "rack"

require "dav/errors"
require "dav/request"
require "dav/response"

module Dav
  module Controllers
    # Base for DAV resource controllers.
    class BaseController

      attr_reader :request, :response

      # sets this controller up to have easy access to a request/response pair
      # @param {Hash} env the rack environment
      def with_env(env)
        @request  = Dav::Request.new(env)
        @response = Dav::Response.new

        self
      end

      # sets the response status and finishes the response
      # @param status [Integer] the http status code for the response
      # @return [Array] the rack response
      def complete(status)
        # remove nils from headers
        response.headers.filter! { _2 }
        response.status = status
        response.finish
      end

      # sets the response status and finishes the response
      # @param status [Integer] the http status code for the response
      # @throws [:complete] the rack response
      def complete!(status) = throw :complete, complete(status)

      # raises in order to stop request processing in the router
      # @param reason [String] a descriptive reason
      # @param status [Integer] the http status code
      # @raise HaltRequest
      def invalid!(reason = nil, status: 400)
        raise Errors::HaltRequest.new(status:), reason
      end

      def failure!(reason = nil, status: 500)
        raise Errors::HaltRequest.new(status:), reason
      end

    end
  end
end
