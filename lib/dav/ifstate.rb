# frozen_string_literal: true

require "parslet"

require "dav/lockid"
require "dav/errors"

module Dav
  # Data object which wraps the `If:` header, presenting a list of predicate
  # clauses and access to submitted lock tokens
  class IfState

    Clause         = Data.define(:uri, :predicates)
    TokenPredicate = Data.define(:inv, :token)
    EtagPredicate  = Data.define(:inv, :etag)

    # @return [IfState] the header parsed into an ifstate
    def self.parse(header)
      return nil if header.nil?

      tree = Parser.new.parse(header)
      res  = Transform.new.apply(tree)
      new(res)
    rescue Parslet::ParseFailed
      raise Errors::MalformedRequestError, "couldnt parse If: header"
    end

    attr_reader :clauses

    def initialize(clauses)
      @clauses = clauses
    end

    # all tokens submitted in this header, regardless of match status
    def submitted_tokens
      clauses.flat_map do |clause|
        clause.predicates.filter { _1.is_a? TokenPredicate }.map(&:token)
      end
    end

    # peglet parser for the If: header
    class Parser < Parslet::Parser

      rule(:sp)  { str(" ").repeat(1) }
      rule(:sp?) { str(" ").repeat(0) }

      rule(:string) do
        str('"') >> ((str("\\") >> any) | (str('"').absent? >> any)).repeat.as(:string) >> str('"')
      end

      rule(:resource_tag) do
        str("<") >> match("[^>]").repeat.as(:rtag) >> str(">")
      end

      rule(:state_token) do
        str("<") >> match("[^>]").repeat.as(:token) >> str(">")
      end

      rule(:entity_tag) do
        str("[") >> (string | match("[^\\]]")).repeat.as(:etag) >> str("]")
      end

      rule(:condition) do
        str("Not").maybe.as(:not) >> sp? >> (state_token | entity_tag)
      end

      rule(:untagged_list) do
        str("(") >> (condition >> sp?).repeat.as(:conditions) >> str(")")
      end

      rule(:tagged_list) do
        resource_tag >> sp? >> untagged_list
      end

      rule(:header) { ((tagged_list >> sp?) | (untagged_list >> sp?)).repeat }
      root(:header)

    end

    # @private
    # simple AST transformer for If: header
    class Transform < Parslet::Transform

      rule(not: simple(:inv), token: simple(:token)) { IfState::TokenPredicate.new(!inv.nil?, LockId.from_token(token.to_s)) }
      rule(not: simple(:inv), etag: simple(:etag))   { IfState::EtagPredicate.new(!inv.nil?, etag.to_s) }

      # without rtag, it resolves to the current request uri
      rule(conditions: subtree(:preds)) { IfState::Clause.new(nil, preds) }

      # otherwise, we've extracted the rtag, and it's the url to check against
      rule(rtag: simple(:uri), conditions: subtree(:preds)) { IfState::Clause.new(uri.to_s, preds) }

    end

  end
end
