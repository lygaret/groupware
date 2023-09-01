require_relative "boot"

require "dry/system"
require "string-inquirer"
require "awesome_print"

module App
  class Container < Dry::System::Container
    use :env, inferrer: -> { Accidental::StringInquirer.upgrade ENV["APP_ENV"] }

    configure do |config|
      config.name = :calcard
      config.root = File.expand_path("..", __dir__)
      config.provider_dirs = ["config/providers"]
      config.registrations_dir = "config/registrations"

      # load path is added

      config.component_dirs.add "app" do |dir|
        dir.auto_register = proc do |component|
          # private modules start with _
          !component.identifier.key.split('.').any? { _1.start_with? "_" }
        end
      end

      config.component_dirs.add "lib" do |dir|
        dir.auto_register = false
      end
    end
  end

  Import = Container.injector
end
