# frozen_string_literal: true

require "rack"
require "nokogiri"

module Dav
  # DAV specific response overload - used to give easy accessors
  # to useful response-specific headers in DAV, and consistent builders
  # for bodies.
  class Response < Rack::Response

    def xml_body(&)
      builder = Nokogiri::XML::Builder.new(&)

      self.body            = [builder.to_xml]
      self["Content-Type"] = "application/xml"
    end

  end
end
