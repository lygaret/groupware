# frozen_string_literal: true

require "digest"

module IOUtil
  class MD5Reader
    def initialize(input)
      @input = input
      @hash  = Digest::MD5.new
    end

    def hash = @hash.hexdigest

    # reader methods as expected by rack body readers

    def close     = @input.close
    def gets(...) = @input.gets(...).tap { @hash << _1 }
    def read(...) = @input.read(...).tap { @hash << _1 }

    def each
      @input.each do |out|
        @hash << out
        yield out
      end
    end
  end
end
