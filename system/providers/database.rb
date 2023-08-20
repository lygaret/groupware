App::Container.register_provider(:database) do
    prepare do
        require "sequel"
        require "logger"

        db = Sequel.connect(ENV['DATABASE_URL'], logger: Logger.new('./log/db.log'))
        register('db.connection', db)
    end

    start do
    end

    stop do
        container['db.connection'].disconnect
    end
end