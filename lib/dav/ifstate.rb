require "parslet"

require "dav/errors"

module Dav

  IfState = Data.define(:clauses) do
    def self.parse(header)
      return nil if header.nil?

      tree = IfStateParser.new.parse(header)
      res  = IfStateTransform.new.apply(tree)
      IfState.new(res)
    rescue Parslet::ParseFailed
      raise MalformedRequestError, "couldnt parse If: header"
    end
  end

  IfStateClause         = Data.define(:uri, :predicates)
  IfStateTokenPredicate = Data.define(:inv, :token)
  IfStateEtagPredicate  = Data.define(:inv, :etag)

  class IfStateParser < Parslet::Parser
    rule(:sp)  { str(' ').repeat(1) }
    rule(:sp?) { str(' ').repeat(0) }

    rule(:string) do
      str('"') >> (str('\\') >> any | str('"').absent? >> any).repeat.as(:string) >> str('"')
    end

    rule(:resource_tag) do
      str('<') >> match("[^>]").repeat.as(:rtag) >> str('>')
    end

    rule(:state_token) do
      str('<') >> match("[^>]").repeat.as(:token) >> str('>')
    end

    rule(:entity_tag) do
      str('[') >> (string | match("[^\\\]]")).repeat.as(:etag) >> str(']')
    end

    rule(:condition) do
      str('Not').maybe.as(:not) >> sp? >> (state_token | entity_tag)
    end

    rule(:untagged_list) do
      str('(') >> (condition >> sp?).repeat.as(:conditions) >> str(')')
    end

    rule(:tagged_list) do
      resource_tag >> sp? >> untagged_list
    end

    rule(:header) { (tagged_list >> sp? | untagged_list >> sp?).repeat }
    root(:header)
  end

  class IfStateTransform < Parslet::Transform
    rule(not: simple(:inv), token: simple(:token))        { IfStateTokenPredicate.new(!inv.nil?, token) }
    rule(not: simple(:inv), etag: simple(:etag))          { IfStateEtagPredicate.new(!inv.nil?, etag) }

    rule(rtag: simple(:uri), conditions: subtree(:preds)) { IfStateClause.new(uri, preds) }
    rule(conditions: subtree(:preds))                     { IfStateClause.new(nil, preds) }
  end
end
