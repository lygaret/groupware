require 'rack'
require 'rack/mime'

module Dav

  class MalformedRequestError < StandardError
  end

  class Request < Rack::Request

    DAV_DEPTHS = %w[infinity 0 1]

    Pathname = Data.define(:basename, :dirname) do
      def self.from_path path
        path_parts = path.split("/")
        basename   = path_parts.pop
        dirname    = path_parts.join("/")

        self.new(basename, dirname)
      end

      def path = [dirname, basename].join("/")
    end

    def initialize(...)
      super(...)

      @pathname = Pathname.from_path path_info
    end

    def path     = @pathname.path
    def dirname  = @pathname.dirname
    def basename = @pathname.basename

    # header access per DAV spec

    # @return Integer, content length, 0 if the header is missing
    # @raises MalformedRequetError if the length can't be parsed as an integer
    def dav_content_length
      @dav_content_length ||= 
        begin
          content_length.nil? ? 0 : Integer(content_length)
        rescue ArgumentError
          raise MalformedRequestError, "content length is not an integer!"
        end
    end

    # @return String, content type, looked up in the mime tables if not provided
    def dav_content_type
      @dav_content_type ||= 
        content_type || Rack::Mime.mime_type(File.extname basename)
    end

    # @return :infinity|Integer, the depth
    # @raises MalformedRequestError if the given depth isn't in DAV_DEPTHS
    def dav_depth default: "infinity"
      @dav_depth ||= 
        begin
          depth = get_header("HTTP_DEPTH")&.downcase || "infinity"
          raise MalformedRequestError, "depth is malformed: #{depth}" unless DAV_DEPTHS.include? depth

          depth == "infinity" ? :infinity : depth.to_i
        end
    end

    # @return {Pathname} the destination path, scoped to this application, or nil if the header is empty
    # @raises MalformedRequestError if the destination path is external
    def dav_destination
      @dav_destination ||= 
        begin
          dest = get_header("HTTP_DESTINATION")
          return nil if dest.nil?

          raise MalformedRequestError, "destination is external!" unless dest.delete_prefix!(base_url)
          raise MalformedRequestError, "destination is external!" unless dest.delete_prefix!(script_name) || script_name == ""

          Pathname.from_path dest
        end
    end

    # @return {Bool,nil} the value of the overwrite header, or nil
    def dav_overwrite?
      overwrite = get_header("HTTP_OVERWRITE")
      overwrite&.downcase&.send(:==, "t")
    end

  end
end