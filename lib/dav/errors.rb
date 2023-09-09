# frozen_string_literal: true

module Dav

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

    def initialize(...)
      super
      @status = 400
    end

  end

end
