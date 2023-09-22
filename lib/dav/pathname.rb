# frozen_string_literal: true

module Dav

  # Represents a path, and gives us easy access to the name and dirname
  Pathname = Data.define(:dirname, :basename) do
    # @return [Pathname] the given path parsed into a path name
    def self.parse(path)
      parts    = path.split("/")
      basename = parts.pop
      dirname  = parts.join("/")

      new(dirname, basename)
    end

    def to_s    = [dirname, basename].join("/")
    def inspect = "Pathname(#{self})"
  end

end
