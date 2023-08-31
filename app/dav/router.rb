require "time"
require "nokogiri"
require "rack/mime"

require "dav/request"
require "ioutil/md5_reader"
require "http/method_router"
require "http/request_path"

require_relative "methods/copy_move"
require_relative "methods/get_head"
require_relative "methods/prop_find_patch"
require_relative "methods/put_delete"

module Dav
  DAV_NSDECL = {d: "DAV:"}
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

    include Methods::CopyMoveMethods
    include Methods::GetHeadMethods
    include Methods::PropFindPatchMethods
    include Methods::PutDeleteMethods

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

    def init_req(...)
      super(...)

      @request = Dav::Request.new(@request.env)
    end

    # ---

    def options *args
      response["Allow"] = OPTIONS_SUPPORTED_METHODS

      halt 204
    end
  end
end
