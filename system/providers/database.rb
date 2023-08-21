App::Container.register_provider(:database) do
    prepare do
        require "sequel"
        require "logger"

        url     = ENV['DATABASE_URL']
        options = {
            logger: Logger.new('./log/db.log'),
            connect_sqls: [
                "PRAGMA journal_mode=WAL"
            ]
        }

        register 'db.connection', Sequel.connect(url, **options)
    end

    stop do
        container['db.connection'].disconnect
    end
end