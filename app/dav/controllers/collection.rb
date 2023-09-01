# frozen_string_literal: true

module Dav
  module Controllers
    class Collection
      def get(_req)
        throw :halt, 204
      end
    end
  end
end
