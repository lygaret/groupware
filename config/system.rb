# frozen_string_literal: true

require_relative "boot"
require_relative "types"

require "dry/system"
require "string-inquirer"

module System
  class Container < Dry::System::Container
    use :env, inferrer: -> { Accidental::StringInquirer.upgrade ENV.fetch("APP_ENV", nil)}

    configure do |config|
      config.name              = :groupware
      config.root              = File.expand_path("..", __dir__)
      config.provider_dirs     = ["config/providers"]
      config.registrations_dir = "config/registrations"

      config.component_dirs.add "app" do |dir|
        dir.auto_register = proc do |component|
          # private modules start with _
          # registered, then, have no private components
          component.identifier.key.split(".").none? { _1.start_with? "_" }
        end
      end
    end
  end

  Import = Container.injector
end
