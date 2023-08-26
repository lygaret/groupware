require "time"
require "nokogiri"
require "pp"
require "rack/mime"

require "ioutil/md5_reader"
require "http/method_router"
require "http/request_path"

require_relative "./methods/copy_move"
require_relative "./methods/get_head"
require_relative "./methods/prop_find_patch"
require_relative "./methods/put_delete"

module Dav

  DAV_NSDECL = { d: "DAV:" }
  DAV_DEPTHS = %w[infinity 0 1]

  OPTIONS_SUPPORTED_METHODS = %w[
    OPTIONS HEAD GET PUT DELETE
    MKCOL COPY MOVE LOCK UNLOCK 
    PROPFIND PROPPATCH
  ].join ","

  class Router < Http::MethodRouter

    include App::Import[
      "logger",
      "repositories.resources"
    ]

    # override to retry on database locked errors
    def call!(...)
      attempted = false
      begin
        super(...)
      rescue Sequel::DatabaseError => ex
        raise unless ex.cause.is_a? SQLite3::BusyException
        raise if attempted

        logger.error "database locked, retrying... #{ex}"
        attempted = true
        retry
      end
    end

    def options *args
      response["Allow"] = OPTIONS_SUPPORTED_METHODS
      halt 204
    end

    include Methods::CopyMoveMethods
    include Methods::GetHeadMethods
    include Methods::PropFindPatchMethods
    include Methods::PutDeleteMethods

    private

    def request_path
      @request_path ||= Http::RequestPath.from_path request.path_info
    end

    def request_content_length
        request.content_length.nil? ? 0 : Integer(request.content_length)
    end

    def request_content_type
        request.content_type || Rack::Mime.mime_type(File.extname request_path.name)
    end

  end
end
