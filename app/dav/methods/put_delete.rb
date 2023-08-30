require 'rack/mime'

module Dav
  module Methods
    module PutDeleteMethods

      # RFC 2518, Section 8.7 - PUT Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_PUT
      def put *args
        resource_id = resources.at_path(request.path).get(:id)
        resource_id.nil? \
          ? put_insert
          : put_update(resource_id)
      end

      # RFC 2518, Section 8.3 - MKCOL Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_MKCOL
      def mkcol *args
        # mkcol w/ body is unsupported
        # not allowed if already exists RFC2518 8.3.2
        halt 415 if request.content_length
        halt 415 if request.media_type
        halt 405 unless resources.at_path(request.path).empty?

        # intermediate collections must already exist
        parent = resources.at_path(request.dirname).select(:id, :coll).first
        halt 409 if     parent.nil?
        halt 409 unless parent[:coll]

        pid  = parent[:id]
        path = request_path.name
        resources.insert(pid:, path:, coll: true)

        halt 201 # created
      end

      # RFC 2518, Section 8.6 DELETE
      # http://www.webdav.org/specs/rfc2518.html#METHOD_DELETE
      def delete *args
        resource_id = resources.at_path(request.path).get(:id)
        halt 404 if resource_id.nil?

        resources.delete(id: resource_id)
        halt 204
      end

      private

      def put_update resource_id
        length        = request.dav_content_length
        type          = request.dav_content_type
        content, etag = read_hash_body length

        resources.update(id: resource_id, type:, length:, content:, etag:)
        halt 204 # no content
      end

      def put_insert
        parent = resources.at_path(request.dirname).select(:id, :coll).first
        halt 404 if     parent.nil?
        halt 409 unless parent[:coll]

        pid           = parent[:id]
        path          = request.basename
        length        = request.dav_content_length
        type          = request.dav_content_type
        content, etag = read_hash_body length

        resources.insert(pid:, path:, type:, length:, content:, etag:)
        halt 201 # created
      end

      def read_hash_body len
        body    = IOUtil::MD5Reader.new request.body
        content = body.read(len) # hashes as a side effect

        [content, body.hash]
      end

    end
  end
end