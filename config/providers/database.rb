System::Container.register_provider(:database) do
  prepare do
    require "cgi"
    require "securerandom"
    require "sequel"
    require "sqlite3"
    require "sqlite3/ext/closure"
  end

  start do
    target.start :logger
    target.start :settings

    db = Sequel.connect(
      target[:settings].database_url,
      logger: target[:logger],
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

    register "database", db
  end

  stop do
    container["database"].disconnect
  end
end
