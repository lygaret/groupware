Application.register_provider(:database) do
    prepare do
        require "sequel"
        Sequel.connect(
            ENV['DB_URL'], 
            sql_log_level: :debug,
            after_connect: proc do |conn|
                conn.enable_load_extension true
                conn.load_extension("./closure")
                conn.enable_load_extension false
            end
        ).tap do |conn|
            container.register(:database, conn)
        end
    end

    stop do
        container[:database].disconnect
    end
end