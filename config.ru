require "rack"

require_relative "config/app"
require "http/logger"

App::Container.finalize!

app = Rack::Builder.new do
  use Http::Logger, App::Container["logger"]
  use Rack::ShowExceptions
  use Rack::Deflater
  use Rack::ConditionalGet
  use Rack::ETag
  run App::Container["dav.router"]
end

run app
