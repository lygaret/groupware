require "dry/system/provider_sources"

module System
  module Types
    LogLevel = Symbol
      .constructor { _1.to_s.downcase.to_sym }
      .enum(:trace, :unknown, :error, :fatal, :warn, :info, :debug)
  end

  Container.register_provider(:settings, from: :dry_system) do
    settings do
      setting :database_url, constructor: Types::FilledString

      setting :log_dir, default: "./log", constructor: Types::FilledString
      setting :log_level, default: :info, constructor: Types::LogLevel
    end
  end
end
