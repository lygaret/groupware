# frozen_string_literal: true

require "digest"

module Utils
  # String reader that can pose as the body in a Rack request,
  # and stream-wise computes the md5 of read data as it sees it.
  class MD5Reader

    def initialize(input)
      @input = input
      @hash  = Digest::MD5.new
    end

    # @return [String] the computed digest of data read so far
    def hexdigest = @hash.hexdigest

    # close the underlying input stream
    def close     = @input.close

    # gets from the underlying input stream
    def gets(...) = @input.gets(...).tap { @hash << _1 }

    # read from the underlying input stream
    def read(...) = @input.read(...).tap { @hash << _1 }

    # each from the underlying input stream
    def each
      @input.each do |out|
        @hash << out
        yield out
      end
    end

  end
end
