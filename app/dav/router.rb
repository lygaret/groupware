require "time"

require "http/method_router"
require "http/request_path"

module Dav
  class Router < Http::MethodRouter

    include App::Import[
      "logger",
      "repositories.resources"
    ]

    attr_reader :request_path

    OPTIONS_SUPPORTED_METHODS = %w[
      OPTIONS HEAD GET PUT DELETE # no post
      MKCOL COPY MOVE LOCK UNLOCK PROPFIND PROPPATCH
    ].join ","

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

    def before_req
      super

      @request_path = Http::RequestPath.from_path @request.path_info
    end

    def options *args
      response["Allow"] = OPTIONS_SUPPORTED_METHODS
      ""
    end

    def head(...)
      get(...) # sets headers and throws
      ""       # but don't include a body in head requests
    end

    def get *args
      resource = resources.at_path(request_path.path).first

      halt 404 if resource.nil?
      halt 202 if resource[:coll] == 1 # no content for collections

      headers = {
        "Last-Modified"  => resource[:updated_at] || resource[:created_at],
        "Content-Type"   => resource[:type],
        "Content-Length" => resource[:length].to_s
      }.reject { |k, v| v.nil? }
      response.headers.merge! headers

      [resource[:content].to_str]
    end

    def put *args
      resource_id = resources.at_path(request_path.path).get(:id)
      if resource_id.nil?
        put_insert
      else
        put_update resource_id
      end
    end

    def put_update resource_id
      len = Integer(request.content_length)
      resources.update(
        id: resource_id,
        type: request.content_type,
        length: len,
        content: request.body.read(len),
      )

      halt 204 # no content
    end

    def put_insert
      resources.connection.transaction do
        # conflict if the parent doesn't exist (or isn't a collection)
        parent = resources.at_path(request_path.parent).select(:id, :coll).first
        halt 404 if parent.nil?
        halt 409 unless parent[:coll]

        # read the body from the request
        len = Integer(request.content_length)

        resources.insert(
          pid: parent[:id], 
          path: request_path.name,
          type: request.content_type,
          length: len,
          content: request.body.read(len),
        )
        halt 201 # created
      end
    end

    def delete *args
      res_id = resources.at_path(request_path.path).select(:id).get(:id)
      halt 404 if res_id.nil?

      resources.delete(id: res_id)
      halt 204
    end

    def mkcol *args
      # mkcol w/ body is unsupported
      halt 415 if request.content_length
      halt 415 if request.media_type

      resources.connection.transaction do
        # not allowed if already exists RFC2518 8.3.2
        halt 405 unless resources.at_path(request_path.path).empty?

        # conflict if the parent doesn't exist (or isn't a collection)
        parent = resources.at_path(request_path.parent).select(:id, :coll).first

        halt 409 if parent.nil?
        halt 409 unless parent[:coll]

        # otherwise, insert!
        resources.insert(
          pid: parent[:id],
          path: request_path.name,
          coll: true
        )
      end

      halt 201 # created
    end

    def post(*args) = halt 405 # method not supported

    def copy(*args) = copy_move clone: true

    def move(*args) = copy_move clone: false

    def copy_move clone:
      # destination needs to be present, and local

      destination = request.get_header "HTTP_DESTINATION"
      halt 400 if destination.nil?
      halt 400 unless destination.delete_prefix!(request.base_url)
      halt 400 unless destination.delete_prefix!(request.script_name) || request.script_name == ""

      destination = Http::RequestPath.from_path destination
      resources.connection.transaction do
        source = resources.at_path(request_path.path).first
        halt 404 if source.nil?

        # fetch the parent collection of the destination
        # conflict if the parent doesn't exist (or isn't a collection)
        parent = resources.at_path(destination.parent).select(:id, :coll).first
        halt 409 if parent.nil?
        halt 409 unless parent[:coll]

        # overwrititng
        extant = resources.at_path(destination.path).select(:id).first
        if !extant.nil?
          overwrite = request.get_header("HTTP_OVERWRITE")&.downcase
          halt 412 unless overwrite == "t"

          resources.delete(id: extant[:id])
        end

        # now we can copy / move
        if clone
          resources.clone_tree source[:id], parent[:id], destination.name
        else 
          resources.move_tree source[:id], parent[:id], destination.name
        end

        halt(extant.nil? ? 201 : 204)
      end
    end

    def propfind *args
      halt 500
    end

    def propget *args
      halt 500
    end

    def propmove *args
      halt 500
    end

  end
end
