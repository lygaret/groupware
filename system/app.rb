require_relative 'boot'
require 'dry/system'

module App
    class Container < Dry::System::Container
        configure do |config|
            config.root = File.expand_path('..', __dir__)
            config.component_dirs.add 'lib'
        end
    end

    Import = Container.injector
end