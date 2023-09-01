# frozen_string_literal: true

module Dav
  module Methods
    module CopyMoveMethods
      # RFC 2518, Section 8.8 - COPY Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_COPY
      def copy(*_args) = copy_move move: true

      # RFC 2518, Section 8.9 - MOVE Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_MOVE
      def move(*_args) = copy_move move: false

      private

      def copy_move(move:)
        resources.connection.transaction do
          source = resources.at_path(request.path).first
          halt 404 if source.nil?

          # fetch the parent collection of the destination
          dest   = request.dav_destination
          parent = resources.at_path(dest.dirname).first

          # conflict if the parent doesn't exist (or somehow isn't a collection)
          halt 409 if parent.nil?
          halt 409 if parent[:colltype].nil?

          # overwrititng
          extant_id = resources.id_at_path(dest.path)
          unless extant_id.nil?
            halt 412 unless request.dav_overwrite?

            resources.delete(id: extant_id)
          end

          # now we can copy / move
          if move
            resources.clone_tree(source[:id], parent[:id], dest.basename)
          else
            resources.move_tree(source[:id], parent[:id], dest.basename)
          end

          # per litmus, 204 if there was already content there
          halt(extant_id.nil? ? 201 : 204)
        end
      end
    end
  end
end
