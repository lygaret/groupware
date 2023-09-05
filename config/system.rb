# frozen_string_literal: true

require_relative "boot"
require_relative "types"

require "dry/system"
require "string-inquirer"

# application runtime
module System

  # dependency injection root for the whole system
  # @see https://dry-rb.org/gems/dry-system/1.0/
  # @example
  #   System::Container.finalize!
  #   System::Container[:logger] # returns the auto-registered logger
  class Container < Dry::System::Container

    use :env, inferrer: -> { Accidental::StringInquirer.upgrade ENV.fetch("APP_ENV", nil) }

    configure do |config|
      config.name              = :groupware
      config.root              = File.expand_path("..", __dir__)
      config.provider_dirs     = ["config/providers"]
      config.registrations_dir = "config/registrations"

      config.component_dirs.add "mod" do |dir|
        dir.auto_register = true
      end

      config.component_dirs.add "lib" do |dir|
        dir.auto_register = false
      end
    end

  end

  # dependency injection auto-injector for {System.Container}
  Import = Container.injector

end
