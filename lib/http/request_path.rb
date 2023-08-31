module Http
  RequestPath = Data.define(:name, :parent) do
    def self.from_path(path_info)
      parts = path_info.split("/")
      RequestPath.new parts.pop, parts.join("/")
    end

    def path
      [parent, name].join("/")
    end
  end
end
