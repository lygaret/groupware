# frozen_string_literal: true

module Dav
  module Errors

    # Error used to halt processing in the router.
    # When raised, the response will immediately be returned to the client
    class HaltRequest < StandardError

      attr_reader :status, :headers

      def initialize(**headers)
        super

        @status  = headers.delete(:status) || 200
        @headers = headers
      end

    end

    # thrown when a request is malformed, either in body or headers
    class MalformedRequestError < HaltRequest

      def initialize(**headers)
        headers = headers.merge(status: 400)
        super(**headers)
      end

    end

  end
end
