# frozen_string_literal: true

module Dav

  # data wrapper for lock ids, which can parse and generate tokens
  LockId = Data.define(:lid) do
    def self.from_token(token)
      return token if token.is_a? LockId

      match = token.match(/^urn:x-groupware:(?<lid>[^?]+)\?=lock$/i)
      match && new(match[:lid])
    end

    def self.from_lid(lid)
      lid.is_a?(LockId) ? lid : new(lid)
    end

    def token = "urn:x-groupware:#{lid}?=lock"
  end

end
