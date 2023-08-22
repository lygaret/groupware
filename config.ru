require "nancy/base"
require_relative "system/app"

class MainApp < Nancy::Base
    get("/") { "hi from nancy" }
    map("/dav") { run App::Container['dav.router'] }
end

App::Container.finalize!
run MainApp.new