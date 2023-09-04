# frozen_string_literal: true

module Dav
  # Error used to halt processing in the router.
  # When raised, the response will immediately be returned to the client
  class HaltRequest < StandardError

    attr_reader :status, :headers

    def initialize(message = nil, **headers)
      super(message)

      @status  = headers.delete(:status) || 200
      @headers = headers
    end

  end
end
