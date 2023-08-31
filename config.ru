require "rack"

require_relative "config/app"

require "http/middleware/dav_header"
require "http/middleware/logger"

App::Container.finalize!

use Rack::Lint
use Rack::TempfileReaper

use Rack::ContentLength
# use Rack::Deflater

use Rack::ShowExceptions
use Http::Middleware::Logger, App::Container["logger"]

use Http::Middleware::DavHeader, supports: "1, 2, 3"
run App::Container["dav.router"]
