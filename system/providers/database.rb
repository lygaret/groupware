App::Container.register_provider(:database) do
    prepare do
        require "sequel"
        require "logger"
    end

    start do
        after_connect = proc do |conn|
            conn.enable_load_extension true

            closure = "./db/ext/closure"
            conn.load_extension(closure)

            conn.enable_load_extension false
        end

        db = Sequel.connect(ENV['DATABASE_URL'], after_connect: after_connect, logger: Logger.new('./log/db.log'))
        register('db.connection', db)
    end

    stop do
        container['db.connection'].disconnect
    end
end