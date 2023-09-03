# frozen_string_literal: true

System::Container.register_provider(:logger) do
  prepare do
    require "ougai"
  end

  start do
    target.start :settings

    logger = Ougai::Logger.new($stdout)

    level        = target[:settings].log_level.to_s.upcase
    logger.level = logger.from_label level

    if target.env.development?
      logger.formatter = Ougai::Formatters::Readable.new
    end

    register "logger", logger
  end
end
