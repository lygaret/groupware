# frozen_string_literal: true

require "rack"
require "rack/constants"

require "dav/errors"
require "dav/pathname"

module Dav
  # Rack application which routes requests to the correct DAV controller.
  #
  # Looks up the path (and possibly that path's parent) in order to find the
  # resource controller handling that path, and then forwards the request.
  class Router

    include System::Import[
      "logger",
      "dav.repos.paths"
    ]

    # rack application entry-point
    # @param env [Hash] the rack hash for the incoming request
    def call(env)
      pathinfo = env[Rack::PATH_INFO]
      methname = env[Rack::REQUEST_METHOD].downcase.to_sym
      pathname = env["dav.pathname"] = Dav::Pathname.parse pathinfo

      # what I would give for pervasive monad syntax and Maybe...

      if pathname.to_s == ""
        # quick bypass for the root
        controller = root_controller
        call_forward(controller, methname, path: nil, ppath: nil, env:)
      else
        # otherwise; look up the path
        pathrow = paths.at_path(pathname.to_s)
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
            parentrow = paths.at_path(pathname.dirname)
            unless parentrow.nil?
              controller = find_controller(parentrow)
              call_forward(controller, methname, path: nil, ppath: parentrow, env:)
            else
              # otherwise it's "missing intermediates", and is likely a 409
              respond methname, "not found", status: 409
            end
          end
        end
      end
    rescue Errors::HaltRequest => e
      body = methname == :head ? "" : e.message
      respond methname, body, status: e.status
    end

    private

    def find_controller(pathrow) = System::Container["dav.controllers.#{pathrow[:pctype]}"]
    def root_controller          = System::Container["dav.controllers.root"]

    def call_forward(controller, methname, path:, ppath:, env:)
      if controller.respond_to? methname
        catch(:complete) do
          controller.with_env(env).send(methname, path:, ppath:)
        end
      else
        respond(methname, "method not supported", status: 405)
      end
    end

    def respond(methname, body, headers: {}, status: 200)
      body = ""     if methname == :head
      body = [body] unless body.respond_to? :each

      [status, headers, body]
    end

  end
end
