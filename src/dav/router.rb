# frozen_string_literal: true

require "rack"
require "rack/constants"

require "dav/_pathname"

module Dav
  class Router

    include System::Import[
      "logger",
      "repos.paths"
    ]

    # rack application entry-point
    # @param env [Hash] the rack hash for the incoming request
    def call(env)
      debugger
      pathinfo = env[Rack::PATH_INFO]
      methname = env[Rack::REQUEST_METHOD].downcase.to_sym
      pathname = Dav::Pathname.parse pathinfo

      if pathname.to_s == ""
        # quick bypass for the root
        controller = get_root_controller
        call_controller(controller, methname, path: nil, ppath: nil, env:)
      else
        # otherwise; look up the path
        pathrow = paths.at_path(pathname.to_s).first
        unless pathrow.nil?
          # if the path exists, use it's inherited controller to handle the method
          controller = get_controller(pathrow)
          call_controller(controller, methname, path: pathrow, ppath: nil, env:)
        else
          if pathname.dirname == ""
            # otherwise; if the parent is the root, use that
            controller = get_root_controller
            call_controller(controller, methname, path: nil, ppath: nil, env:)
          else
            # otherwise; look up the parent
            parentrow = paths.at_path(pathname.dirname).first
            unless parentrow.nil?
              controller = get_controller(parentrow)
              call_controller(controller, methname, path: nil, ppath: parentrow, env:)
            else
              # otherwise it's completely not for us, 404
              [404, {}, ["not found"]]
            end
          end
        end
      end
    end

    private

    def call_controller(controller, methname, path:, ppath:, env:)
      return [405, {}, ["method not supported"]] unless controller.respond_to? methname

      controller.send(methname, path:, ppath:, env:)
    end

    def get_controller pathrow
      System::Container["dav.controllers.#{pathrow[:pctype]}"]
    end

    def get_root_controller
       System::Container["dav.controllers.root"]
    end

  end
end
