require 'securerandom'

module Utils
  module Base58

    ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".split('').freeze

    def self.random_base58(n = nil)
      bytes = SecureRandom.random_bytes(n).unpack("S*")
      chars = bytes.flat_map { _1.digits 58 }
      ALPHABET.values_at(*chars).join
    end

  end
end
