# frozen_string_literal: true

require "dry/system/provider_sources"

module System
  module Types

    LogLevel = Symbol
                 .constructor { _1.to_s.downcase.to_sym }
                 .enum(:trace, :unknown, :error, :fatal, :warn, :info, :debug)

  end
end

System::Container.register_provider(:settings, from: :dry_system) do
  settings do
    setting :database_url, constructor: System::Types::FilledString

    setting :host, default: "localhost", constructor: System::Types::FilledString
    setting :port, default: 5000,        constructor: System::Types::Params::Integer

    setting :log_level, default: :info, constructor: System::Types::LogLevel
  end
end
