# frozen_string_literal: true

require "ougai"

module System
  module Providers
    module Logger
      # minorly customized format for log messages in development
      class DevFormat < Ougai::Formatters::Readable

        def call(severity, time, _progname, data)
          @excluded_fields.each { |f| data.delete(f) }

          msg     = data.delete(:msg)
          syst    = data.delete(:system)&.then { _1.to_s.rjust(8) } || "".rjust(8)
          sanserr = data.except(:err)
          level   = @plain ? severity : colored_level(severity)

          strs    = ["#{level}#{syst} [#{time.utc.strftime('%H%M%S.%L')}]: #{msg} #{sanserr.inspect}"]

          err_str = create_err_str(data)
          strs.push err_str if err_str

          "#{strs.join("\n")}\n"
        end

      end
    end
  end
end

System::Container.register_provider(:logger) do
  start do
    target.start :settings

    logger = Ougai::Logger.new($stdout)

    level        = target[:settings].log_level.to_s.upcase
    logger.level = logger.from_label level

    logger.formatter = System::Providers::Logger::DevFormat.new if target.env.development?

    register "logger", logger
  end
end
