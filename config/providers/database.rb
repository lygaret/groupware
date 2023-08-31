require "cgi"
require "securerandom"

App::Container.register_provider(:database) do
  prepare do
    require "sequel"
  end

  start do
    target.start :logger
    target.start :settings

    db = Sequel.connect(
      target[:settings].database_url,
      logger: target[:logger],
      connect_sqls: [
        "PRAGMA journal_mode=WAL"
      ],
      after_connect:
        proc do |c|
          c.create_function("uuid", 0) do |func|
            func.result = SecureRandom.uuid
          end
          c.create_function("unescape_url", 1) do |func, str|
            func.result = CGI.unescape str
          end
        end
    )

    register "db.connection", db
  end

  stop do
    container["db.connection"].disconnect
  end
end
