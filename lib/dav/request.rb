# frozen_string_literal: true

require "rack"
require "rack/mime"

require "dav/errors"
require "dav/ifstate"
require "dav/pathname"
require "utils/md5_reader"

module Dav
  # DAV specific request overload - used to give easy accessors
  # to useful request-specific headers in DAV, such as the parsed
  # path, Destination header, If header handling, etc.
  class Request < Rack::Request

    DAV_DEPTHS      = %w[infinity 0 1].freeze
    DAV_MAX_TIMEOUT = 30 * 24 * 60 * 60 * 60 # 30 days

    # @return [Pathname] the pathname recovered from the rack environment
    def path = env["dav.pathname"]

    # @return [String] fullpath as a string
    def fullpath = super.to_s

    # @return [Utils::MD5Reader] a body wrapper which computes the md5 as it's being read.
    def md5_body
      @md5_body ||= Utils::MD5Reader.new(body)
    end

    # @return [Boolean] is the content-type xml?
    def xml_body?(allow_nil: false)
      (allow_nil && content_type.nil?) || content_type =~ %r{(text|application)/xml}
    end

    # @return [Nokogiri::XML::Document] the body parsed as xml
    # @raise MalformedRequestError if the body cannot be parsed
    def xml_body
      @xml_body ||=
        begin
          content = body.gets
          if content.nil? || content == ""
            nil
          else
            Nokogiri::XML.parse(content) { |config| config.strict.pedantic.nsclean }
          end
        rescue StandardError
          raise Errors::MalformedRequestError.new(status: 400), "couldn't parse xml body!"
        end
    end

    # @return Integer, content length, 0 if the header is missing
    # @raise MalformedRequetError if the length can't be parsed as an integer
    def dav_content_length
      @dav_content_length ||=
        begin
          content_length.nil? ? 0 : Integer(content_length)
        rescue ArgumentError
          raise Errors::MalformedRequestError, "content length is not an integer!"
        end
    end

    # @return String, content type, looked up in the mime tables if not provided
    def dav_content_type
      @dav_content_type ||=
        content_type || Rack::Mime.mime_type(File.extname(path.basename))
    end

    # @return :infinity|Integer, the depth
    # @raise MalformedRequestError if the given depth isn't in DAV_DEPTHS
    def dav_depth(default: "infinity")
      @dav_depth ||=
        begin
          depth = get_header("HTTP_DEPTH")&.downcase || default
          raise Errors::MalformedRequestError, "depth is malformed: #{depth}" unless DAV_DEPTHS.include? depth

          depth == "infinity" ? :infinity : depth.to_i
        end
    end

    # @return {Pathname} the destination path, scoped to this application, or nil if the header is empty
    # @raise MalformedRequestError if the destination path is external
    def dav_destination
      @dav_destination ||=
        begin
          dest = get_header("HTTP_DESTINATION")
          unless dest.nil?
            raise Errors::MalformedRequestError, "destination is external!" unless dest.delete_prefix!(base_url)
            unless dest.delete_prefix!(script_name) || script_name == ""
              raise Errors::MalformedRequestError, "destination is external!"
            end
          end

          dest && Pathname.parse(dest)
        end
    end

    # @return {Bool,nil} the value of the overwrite header, or nil
    def dav_overwrite?
      overwrite = get_header("HTTP_OVERWRITE")
      overwrite&.downcase&.send(:==, "t")
    end

    # @return Integer requested timeouts, up to the given max
    def dav_timeout(max: DAV_MAX_TIMEOUT)
      timeout = get_header("HTTP_TIMEOUT")
      if timeout.nil? || timeout == ""
        nil
      else
        timeout.split(",").map do |ts|
          if ts == "Infinite"
            max
          elsif (match = /Second-(\d+)/.match(ts))
            [match[1].to_i, max].min
          else
            raise Errors::MalformedRequestError, "bad timeout format!" unless match
          end
        end
      end.min
    end

    def dav_ifstate
      @dav_ifstate ||= IfState.parse get_header("HTTP_IF")
    end

    def dav_locktoken
      @dav_locktoken ||= begin
        header = get_header("HTTP_LOCK_TOKEN")
        header&.sub(/<([^>]+)>/, "\\1")
      end
    end

    def dav_submitted_tokens
      iftokens  = dav_ifstate&.submitted_tokens&.dup || []
      iftokens << dav_locktoken if dav_locktoken

      iftokens
    end

  end
end
