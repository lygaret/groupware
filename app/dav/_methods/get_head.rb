# frozen_string_literal: true

module Dav
  module Methods
    module GetHeadMethods
      def get(*_args)
        resource = resources.at_path(request.path).first
        halt 404 if resource.nil?

        if resource[:colltype].nil?
          response.headers.merge! resource_headers(resource)
          [resource[:content].to_str] # array because bodies must be enumerable
        else
          cont = App::Container["dav.controllers.#{resource[:colltype]}"]
          cont.get resource, request
        end
      end

      def head(...)
        get(...) # sets headers and throws
        []       # no content
      end

      private

      def resource_headers(res)
        headers = {
          "Content-Type" => res[:type],
          "Content-Length" => res[:length].to_s,
          "Last-Modified" => res[:updated_at] || res[:created_at],
          "ETag" => res[:etag]
        }

        headers.reject { _2.nil? }
      end
    end
  end
end
