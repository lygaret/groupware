# frozen_string_literal: true

require "ougai"

module System
  module Providers
    module Logger
      # simple, nicely colored, single-line
      # minorly customized format for log messages in development
      class DevFormat < Ougai::Formatters::Readable

        def call(severity, time, _progname, data)
          @excluded_fields.each { |f| data.delete(f) }

          err   = create_err_str(data)
          data  = data.except(:err)

          level = @plain ? severity : colored_level(severity)
          time  = time.strftime("%H%M%S.%L%z")
          syst  = data.delete(:system)

          strs  = ["#{time} #{level} #{syst} #{data.ai(multiline: false)}"]
          strs << err if err

          "#{strs.join("\n")}\n"
        end

      end
    end
  end
end

System::Container.register_provider(:logger) do
  start do
    target.start :settings

    level = target[:settings].log_level.to_s.upcase

    logger           = Ougai::Logger.new($stdout)
    logger.level     = logger.from_label level
    logger.formatter = System::Providers::Logger::DevFormat.new if target.env.development?

    register "logger", logger
  end
end
