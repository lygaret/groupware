# frozen_string_literal: true

module Dav
  class HaltRequest < StandardError

    attr_reader :status, :headers

    def initialize(message = nil, **headers)
      super(message)

      @status  = headers.delete(:status) || 200
      @headers = headers
    end

  end
end
