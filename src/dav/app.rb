# frozen_string_literal: true

require "rack"

module Dav
  class App

    include System::Import[
      "logger",
      "repos.paths"
    ]

    attr_reader :request, :respons, :env

    # rack application entry-point
    # @param env [Hash] the rack hash for the incoming request
    def call(env)
      @request  = Rack::Request.new(env)
      @response = Rack::Response.new
      @env      = env

      catch(:halt) do
      end

      @response.finish
    end

    def halt = throw :halt

  end
end
