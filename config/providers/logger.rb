require "securerandom"

App::Container.register_provider(:logger) do
  prepare do
    require "logger"
  end

  start do
    target.start :settings

    log_file = File.join(target[:settings].log_dir, "#{target.env}.log")

    logger = Logger.new(log_file)
    logger.level = target[:settings].log_level

    register(:logger, logger)
  end
end
