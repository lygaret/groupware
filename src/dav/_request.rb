# frozen_string_literal: true

require "rack"

module Dav
  # DAV specific request overload - used to give easy accessors
  # to useful request-specific headers in DAV, such as the parsed
  # path, Destination header, If header handling, etc.
  class Request < Rack::Request

    def path = env["dav.pathname"]

  end
end
