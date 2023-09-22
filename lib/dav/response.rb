# frozen_string_literal: true

require "rack"
require "nokogiri"

module Dav
  # DAV specific response overload - used to give easy accessors
  # to useful response-specific headers in DAV, and consistent builders
  # for bodies.
  class Response < Rack::Response

    # respond with xml body, built from a nokogiri builder,
    # and appropriately set the content type header.
    #
    # @yield [Nokogiri::XML::Builder] the builder for the response
    def xml_body(&)
      self["Content-Type"] = "application/xml"

      # TODO: builder _outside_ the response proc means that we run
      # the block immediately; would it better if the block were run
      # conditionally? is that unexpected?

      builder   = Nokogiri::XML::Builder.new(&)
      self.body = proc do |out|
        builder.doc.write_to(out, indent: 2)
      end
    end

  end
end
