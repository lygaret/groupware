module Dav
  module Methods
    module GetHeadMethods
      def get *args
        resource = resources.at_path(request.path).first

        halt 404 if resource.nil?
        halt 204 if resource[:coll] == 1 # no content for collections

        response.headers.merge! resource_headers(resource)
        [resource[:content].to_str] # array because bodies must be enumerable
      end

      def head(...)
        get(...) # sets headers and throws
        halt 204 # no content
      end

      private

      def resource_headers res
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
