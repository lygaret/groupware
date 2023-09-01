# frozen_string_literal: true

require_relative "boot"

require "dry/system"
require "string-inquirer"

module App
  class Container < Dry::System::Container
    use :env, inferrer: -> { Accidental::StringInquirer.upgrade ENV.fetch("APP_ENV", nil) }

    configure do |config|
      config.name              = :calcard
      config.root              = File.expand_path("..", __dir__)
      config.provider_dirs     = ["config/providers"]
      config.registrations_dir = "config/registrations"

      # load path is added

      config.component_dirs.add "app" do |dir|
        dir.auto_register = proc do |component|
          # private modules start with _
          # registered modules have no private components
          component.identifier.key.split(".").none? { _1.start_with? "_" }
        end
      end

      config.component_dirs.add "lib" do |dir|
        dir.auto_register = false
      end
    end
  end

  Import = Container.injector
end
