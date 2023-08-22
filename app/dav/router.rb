require "time"
require "http/router"

module Dav
  class Router < Http::Router
    include App::Import[
      "logger",
      "repositories.resources"
    ]

    def call!(...)
      attempted = false
      begin
        super(...)
      rescue Sequel::DatabaseError => ex
        raise unless ex.cause.is_a? SQLite3::BusyException
        raise if attempted

        attempted = true
        logger.error "database locked, retrying... #{ex}"
        retry
      end
    end

    before do
      response["DAV"] = "1"
    end

    def parse_paths path_info
      parts = path_info.split("/")
      [parts.pop, parts.join("/")]
    end

    def options *args
      response["Allow"] = "OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK"
      halt 200
    end

    def head(*)
      get(*) # sets headers and throws
      nil    # but don't include a body in head requests
    end

    def get *args
      resource = resources.at_path(request.path_info).first

      halt 404 if resource.nil?
      halt 202 if resource[:coll] == 1 # no content for collections

      headers = {
        "Last-Modified" => resource[:updated_at] || resource[:created_at],
        "Content-Type" => resource[:type]
      }.reject { |k, v| v.nil? }
      response.headers.merge! headers

      resource[:content]
    end

    def put *args
      resource_id = resources.at_path(request.path_info).select(:id).get(:id)
      if resource_id.nil?
        put_insert
      else
        put_update resource_id
      end
    end

    def put_update resource_id
      len = Integer(request.content_length)
      resources.resources
        .where(id: resource_id)
        .update(
          type: request.content_type,
          content: request.body.read(len),
          length: len,
          updated_at: Time.now.utc
        )

      halt 204 # no content
    end

    def put_insert
      resources.connection.transaction do
        # fetch the parent collection
        # conflict if the parent doesn't exist (or isn't a collection)
        parent_path, name = split_path request.path_info
        parent = resources.at_path(parent_path).select(:id, :coll).first

        # conflict if the parent isn't a collection?
        halt 404 if parent.nil?
        halt 409 unless parent[:coll]

        # read the body from the request
        len = Integer(request.content_length)
        resources.resources.insert(
          id: Sequel.function(:uuid),
          pid: parent[:id],
          path: name,

          type: request.content_type,
          content: request.body.read(len),
          length: len,

          created_at: Time.now.utc
        )

        halt 201 # created
      end
    end

    def delete *args
      res_id = resources.at_path(request.path_info).select(:id).get(:id)
      halt 404 if res_id.nil?

      # deletes cascade with parent_id
      resources.resources.where(id: res_id).delete
      halt 204 # no content
    end

    def mkcol *args
      # mkcol w/ body is unsupported
      halt 415 if request.content_length
      halt 415 if request.media_type

      resources.connection.transaction do
        # not allowed if already exists RFC2518 8.3.2
        halt 405 unless resources.at_path(request.path_info).empty?

        # fetch the parent collection
        # conflict if the parent doesn't exist (or isn't a collection)
        parent_path, name = split_path request.path_info
        parent = resources.at_path(parent_path).select(:id, :coll).first

        halt 409 if parent.nil?
        halt 409 unless parent[:coll]

        # otherwise, insert!
        resources.resources.insert(
          id: Sequel.function(:uuid),
          pid: parent[:id],
          path: name,
          coll: true,
          created_at: Time.now
        )

        halt 201 # created
      end
    end

    def post(*args) = halt 405 # method not supported

    def copy(*args) = copy_move clone: true

    def move(*args) = copy_move clone: false

    def copy_move clone:
      # destination needs to be present, and local

      destination = request.get_header "HTTP_DESTINATION"
      halt 400 if destination.nil?
      halt 400 unless destination.delete_prefix!(request.base_url)
      halt 400 unless request.script_name == "" || destination.delete_prefix!(request.script_name)

      resources.connection.transaction do
        source = resources.at_path(request.path_info).first
        halt 404 if source.nil?

        # fetch the parent collection of the destination
        # conflict if the parent doesn't exist (or isn't a collection)

        parent_path, name = split_path destination
        parent = resources.at_path(parent_path).select(:id, :coll).first

        halt 409 if parent.nil?
        halt 409 unless parent[:coll]

        # overwrititng

        extant = resources.at_path(destination).select(:id).first
        if !extant.nil?
          overwrite = request.get_header("HTTP_OVERWRITE")&.downcase
          halt 412 unless overwrite == "t"

          resources.resources.where(id: extant[:id]).delete
        end

        # now we can copy / move

        if clone
          resources.clone_tree source[:id], parent[:id], name
        else # move
          resources.move_tree source[:id], parent[:id], name
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

    private

    def split_path(path)
      parts = path.split("/")
      leaf = parts.pop

      [parts.join("/"), leaf]
    end
  end
end
