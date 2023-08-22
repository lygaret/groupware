require "dry/types"
require "dry/system/provider_sources"

App::Container.register_provider(:settings, from: :dry_system) do
  settings do
    # env vars are here as expected

    setting :database_url,
      constructor: Dry::Types["string"].constrained(filled: true)

    setting :log_dir, default: "./log",
      constructor: Dry::Types["string"].constrained(filled: true)

    setting :log_level,
      default: :info,
      constructor: Dry::Types["symbol"]
        .constructor { |value| value.to_s.downcase.to_sym }
        .enum(:trace, :unknown, :error, :fatal, :warn, :info, :debug)
  end
end
