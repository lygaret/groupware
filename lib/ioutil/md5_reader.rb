require "digest"

module IOUtil
  class MD5Reader
    def initialize(input)
      @input = input
      @hash = Digest::MD5.new
    end

    def hash = @hash.hexdigest

    def close = @input.close

    def gets
      @input.gets.tap do |output|
        @hash << output
      end
    end

    def read(...)
      @input.read(...).tap do |output|
        @hash << output
      end
    end

    def each
      @input.each do |out|
        @hash << out
        yield out
      end
    end
  end
end
