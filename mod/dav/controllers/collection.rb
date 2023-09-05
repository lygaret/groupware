# frozen_string_literal: true

require "utils/md5_reader"
require "dav/controllers/base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
    class Collection < BaseController

      include System::Import[
        "repos.paths",
        "logger"
      ]

      OPTIONS_SUPPORTED_METHODS = %w[
        OPTIONS HEAD GET PUT DELETE
        MKCOL COPY MOVE LOCK UNLOCK
        PROPFIND PROPPATCH
      ].join(",").freeze

      def options(*)
        response["Allow"] = OPTIONS_SUPPORTED_METHODS
        complete 204
      end

      def head(path:, ppath:)
        get(path:, ppath:, include_body: false)
      end

      def get(path:, ppath:, include_body: true)
        invalid! "not found", status: 404 if path.nil?

        if path[:ctype]
          # no content for a collection
          complete 204
        else
          resource = paths.resource_at(pid: path[:id]).first
          if resource.nil?
            complete 204 # no content at path!
          else
            headers  = {
              "Content-Type" => resource[:type],
              "Content-Length" => resource[:length].to_s,
              "Last-Modified" => resource[:updated_at] || resource[:created_at],
              "ETag" => resource[:etag]
            }
            headers.reject! { _2.nil? }

            response.body = [resource[:content]] if include_body
            response.headers.merge! headers

            complete 200
          end
        end
      end

      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # path itself can't already exist
        invalid! "path already exists", status: 405 unless path.nil?

        # intermediate collections must already exist
        # but at the root, there's no parent
        has_inter   = !ppath.nil?
        has_inter ||= request.path.dirname == ""
        invalid! "intermediate paths must exist", status: 409 unless has_inter

        paths.insert(pid: ppath&.[](:id), path: request.path.basename, ctype: "collection")
        complete 201 # created
      end

      def put(path:, ppath:)
        if path.nil?
          put_insert(ppath:)
        else
          put_update(path:)
        end
      end

      def delete(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?

        paths.delete(id: path[:id])
        complete 204 # no content
      end

      def copy(path:, ppath:) = copy_move path:, ppath:, move: false
      def move(path:, ppath:) = copy_move path:, ppath:, move: true

      private

      def put_insert(ppath:)
        invalid! "intermediate path not found", status: 409 if ppath.nil?
        invalid! "parent must be a collection", status: 409 if ppath[:ctype].nil?

        paths.transaction do
          pid  = ppath[:id]
          path = request.path.basename

          # the new path is the parent of the resource
          id = paths.insert(pid:, path:, ctype: nil)

          type          = request.dav_content_type
          length        = request.dav_content_length
          content, etag = read_md5_body(request.body, length)

          # insert the resource at that path
          paths.put_resource(id:, length:, type:, content:, etag:)
        end

        complete 201
      end

      def put_update(path:)
        invalid "not found", status: 404 if path.nil?

        type          = request.dav_content_type
        length        = request.dav_content_length
        content, etag = read_md5_body(request.body, length)

        paths.transaction do
          paths.resource_at(id: path[:id]).delete
          paths.put_resource(id: path[:id], length:, type:, content:, etag:)
        end

        complete 204
      end

      def copy_move(path:, ppath:, move:)
        invalid! "not found", status: 404 if path.nil?

        paths.transaction do
          dest  = request.dav_destination
          pdest = paths.at_path(dest.dirname)

          invalid! "destination root must exist", status: 409           if pdest.nil?
          invalid! "destination root must be a collection", status: 409 if pdest[:ctype].nil?

          extant = paths.at_path(dest.to_s)
          unless extant.nil?
            invalid! "destination must not already exist", status: 412 unless request.dav_overwrite?

            paths.delete(id: extant[:id])
          end

          if move
            paths.move_tree(id: path[:id], dpid: pdest[:id], dpath: dest.basename)
          else
            paths.clone_tree(id: path[:id], dpid: pdest[:id], dpath: dest.basename)
          end

          status = extant.nil? ? 201 : 204
          complete status
        end
      end

      def read_md5_body(input, len)
        body = Utils::MD5Reader.new(input)
        data = body.read(len)

        [data, body.hexdigest]
      end

    end
  end
end
