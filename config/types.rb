# frozen_string_literal: true

require "dry-types"
require "dry-struct"

module System
  # shared types, for use in validators, settingsn, etc.
  # @see https://dry-rb.org/gems/dry-types/1.2/
  module Types

    include Dry.Types()

    FilledString = String.constrained(filled: true)

  end
end
