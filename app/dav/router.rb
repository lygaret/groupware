# frozen_string_literal: true

require "time"
require "nokogiri"
require "rack/mime"

require "ioutil/md5_reader"
require "http/method_router"
require "http/request_path"

require_relative "_http/request"
require_relative "_methods/copy_move"
require_relative "_methods/get_head"
require_relative "_methods/prop_find_patch"
require_relative "_methods/put_delete"

module Dav
  DAV_NSDECL = { d: "DAV:" }.freeze
  DAV_DEPTHS = %w[infinity 0 1].freeze

  OPTIONS_SUPPORTED_METHODS = %w[
    OPTIONS HEAD GET PUT DELETE
    MKCOL COPY MOVE LOCK UNLOCK
    PROPFIND PROPPATCH
  ].join(",").freeze

  class Router < ::Http::MethodRouter
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
      rescue Sequel::DatabaseError => e
        raise unless e.cause.is_a? SQLite3::BusyException
        raise if attempted

        logger.error "database locked, retrying... #{e}"
        attempted = true
        retry
      end
    end

    def init_req(...)
      super(...)

      @request = Dav::Http::Request.new(@request.env)
    end

    # ---

    def options *_args
      response["Allow"] = OPTIONS_SUPPORTED_METHODS

      halt 204
    end
  end
end
