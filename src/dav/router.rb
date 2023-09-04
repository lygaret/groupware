# frozen_string_literal: true

require "rack"
require "rack/constants"

require "dav/_errors"
require "dav/_pathname"

module Dav
  # Rack application which routes requests to the correct DAV controller.
  #
  # Looks up the path (and possibly that path's parent) in order to find the
  # resource controller handling that path, and then forwards the request.
  class Router

    include System::Import[
      "logger",
      "repos.paths"
    ]

    # rack application entry-point
    # @param env [Hash] the rack hash for the incoming request
    def call(env)
      pathinfo = env[Rack::PATH_INFO]
      methname = env[Rack::REQUEST_METHOD].downcase.to_sym
      pathname = env["dav.pathname"] = Dav::Pathname.parse pathinfo

      if pathname.to_s == ""
        # quick bypass for the root
        controller = root_controller
        call_forward(controller, methname, path: nil, ppath: nil, env:)
      else
        # otherwise; look up the path
        pathrow = paths.at_path(pathname.to_s).first
        unless pathrow.nil?
          # if the path exists, use it's inherited controller to handle the method
          controller = find_controller(pathrow)
          call_forward(controller, methname, path: pathrow, ppath: nil, env:)
        else
          if pathname.dirname == ""
            # otherwise; if the parent is the root, use that
            controller = root_controller
            call_forward(controller, methname, path: nil, ppath: nil, env:)
          else
            # otherwise; look up the parent
            parentrow = paths.at_path(pathname.dirname).first
            unless parentrow.nil?
              controller = find_controller(parentrow)
              call_forward(controller, methname, path: nil, ppath: parentrow, env:)
            else
              # otherwise it's completely not for us, 404
              respond methname, body, status: 404
            end
          end
        end
      end
    end

    private

    def find_controller(pathrow) = System::Container["dav.controllers.#{pathrow[:pctype]}"]
    def root_controller          = System::Container["dav.controllers.root"]

    def call_forward(controller, methname, path:, ppath:, env:)
      return respond("method not supported", status: 400) unless controller.respond_to? methname

      begin
        controller.with_env(env).send(methname, path:, ppath:)
      rescue HaltRequest => e
        respond methname, e.message, status: e.status
      end
    end

    def respond(methname, body, headers: {}, status: 200)
      body = ""     if methname == :head
      body = [body] unless body.respond_to? :each

      [status, headers, body]
    end

  end
end
