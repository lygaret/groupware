require "securerandom"

App::Container.register_provider(:database) do
  prepare do
    require "sequel"
    require "logger"

    url = ENV["DATABASE_URL"]
    options = {
      logger: Logger.new("./log/db.log"),
      connect_sqls: [
        "PRAGMA journal_mode=WAL"
      ],
      after_connect: proc do |c|
                       c.create_function("uuid", 0) do |func|
                         func.result = SecureRandom.uuid
                       end
                     end
    }

    db = Sequel.connect(url, **options)
    register "db.connection", db
  end

  stop do
    container["db.connection"].disconnect
  end
end
