module Dav
  module Methods
    module CopyMoveMethods

      # RFC 2518, Section 8.8 - COPY Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_COPY
      def copy(*args) = copy_move move: true

      # RFC 2518, Section 8.9 - MOVE Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_MOVE
      def move(*args) = copy_move move: false

      private

      def copy_move move:
        resources.connection.transaction do
          source = resources.at_path(request_path.path).first
          halt 404 if source.nil?

          # fetch the parent collection of the destination
          dest   = copy_move_destination request
          parent = resources.at_path(dest.parent).select(:id, :coll).first

          # conflict if the parent doesn't exist (or somehow isn't a collection)
          halt 409 if parent.nil?
          halt 409 unless parent[:coll]

          # overwrititng
          extant_id = resources.at_path(dest.path).get(:id)
          if !extant_id.nil?
            overwrite = request.get_header("HTTP_OVERWRITE")&.downcase
            halt 412 unless overwrite == "t"

            resources.delete(id: extant_id)
          end

          # now we can copy / move
          move \
            ? resources.clone_tree(source[:id], parent[:id], dest.name)
            : resources.move_tree(source[:id], parent[:id], dest.name)

          # per litmus, 204 if there was already content there
          halt(extant_id.nil? ? 201 : 204)
        end
      end

      # extract the destination header, as a requestpath object
      def copy_move_destination request
        destination = request.get_header("HTTP_DESTINATION")

        # destination needs to be present, and local
        halt 400 if destination.nil?
        halt 400 unless destination.delete_prefix!(request.base_url)
        halt 400 unless destination.delete_prefix!(request.script_name) || request.script_name == ""

        Http::RequestPath.from_path destination
      end

    end
  end
end