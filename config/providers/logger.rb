# frozen_string_literal: true

require "ougai"

module System
  module Providers # :nodoc: all
    module Logger
      class CustomFormat < Ougai::Formatters::Readable
        def call(severity, time, _progname, data)
          msg = data.delete(:msg)
          @excluded_fields.each { |f| data.delete(f) }

          sanserr     = data.except(:err)
          level       = @plain ? severity : colored_level(severity)
          strs        = ["[#{time.iso8601(3)}] #{level}: #{msg} (#{sanserr.inspect})"]
          if (err_str = create_err_str(data))
            strs.push(err_str)
          end
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

    logger.formatter = System::Providers::Logger::CustomFormat.new if target.env.development?

    register "logger", logger
  end
end
