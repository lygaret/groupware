# frozen_string_literal: true

module Dav

  # Represents a path, and gives us easy access to the name and dirname
  Pathname = Data.define(:basename, :dirname) do
    def self.parse(path)
      parts    = path.split("/")
      basename = parts.pop
      dirname  = parts.join("/")

      new(basename, dirname)
    end

    def to_s = [dirname, basename].join("/")
  end

end
