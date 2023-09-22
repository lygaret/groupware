# frozen_string_literal: true

module Dav

  # data wrapper for lock ids, which can parse and generate tokens
  LockId = Data.define(:lid) do
    # @return [LockId, nil] returns a lockid or nil, after checking the token format
    def self.from_token(token)
      return token if token.is_a? LockId

      match = token.match(/^urn:x-groupware:(?<lid>[^?]+)\?=lock$/i)
      match && new(match[:lid])
    end

    # @return [LockId] returns a lockid for the given lid
    def self.from_lid(lid)
      lid.is_a?(LockId) ? lid : new(lid)
    end

    # @return [String] the lock token representing this id
    def token = "urn:x-groupware:#{lid}?=lock"
  end

end
