require "rack"

require_relative "config/app"
require "http/logger"

App::Container.finalize!

use Rack::ContentLength
use Rack::Deflater

use Http::Logger, App::Container["logger"]
use Rack::ShowExceptions

use Rack::Lint
use Rack::TempfileReaper

run App::Container["dav.router"]
