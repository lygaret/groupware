# frozen_string_literal: true

require "rack"

module Dav
  class Request < Rack::Request

    def path = env["dav.pathname"]

  end
end
