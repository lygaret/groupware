require 'dry-types'
require 'dry-struct'

module System
  module Types
    include Dry.Types()

    FilledString = String.constrained(filled: true)
  end
end
