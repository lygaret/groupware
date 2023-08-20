require 'http/router'

module Dav
    class Router < Http::Router

        include App::Import['db.resource_repo']

    # 9.3 MKCOL Method
    # MKCOL creates a new collection resource at the location specified by the Request-URI. If the Request-URI is already mapped to a resource, then the MKCOL MUST fail. 
    # During MKCOL processing, a server MUST make the Request-URI an internal member of its parent collection, unless the Request-URI is "/". If no such ancestor exists, 
    # the method MUST fail. When the MKCOL operation creates a new collection resource, all ancestors MUST already exist, or the method MUST fail with a 409 (Conflict)
    # status code. For example, if a request to create collection /a/b/c/d/ is made, and /a/b/c/ does not exist, the request must fail.
    #
    # When MKCOL is invoked without a request body, the newly created collection SHOULD have no members.
    #
    # A MKCOL request message may contain a message body. The precise behavior of a MKCOL request when the body is present is undefined, but limited to creating 
    # collections, members of a collection, bodies of members, and properties on the collections or members. If the server receives a MKCOL request entity type it does 
    # not support or understand, it MUST respond with a 415 (Unsupported Media Type) status code. If the server decides to reject the request based on the presence of 
    # an entity or the type of an entity, it should use the 415 (Unsupported Media Type) status code.
    #
    # This method is idempotent, but not safe (see Section 9.1 of [RFC2616]). Responses to this method MUST NOT be cached.

    # 9.3.1. MKCOL Status Codes
    # In addition to the general status codes possible, the following status codes have specific applicability to MKCOL:
    # - 201 (Created) - The collection was created.
    # - 403 (Forbidden) - This indicates at least one of two conditions: 1) the server does not allow the creation of collections at the given location in its URL 
    #     namespace, or 2) the parent collection of the Request-URI exists but cannot accept members.
    # - 405 (Method Not Allowed) - MKCOL can only be executed on an unmapped URL.
    # - 409 (Conflict) - A collection cannot be made at the Request-URI until one or more intermediate collections have been created. The server MUST NOT create those 
    #     intermediate collections automatically.
    # - 415 (Unsupported Media Type) - The server does not support the request body type (although bodies are legal on MKCOL requests, since this specification doesn't 
    #     define any, the server is likely not to support any given body type).
    # - 507 (Insufficient Storage) - The resource does not have sufficient space to record the state of the resource after the execution of this method.

        def parse_paths(path_info)
            parts = path_info.split("/")
            [parts.pop, parts.join("/")]
        end

        def options *args
            response.headers["DAV"] = "1, 2"
            halt 200
        end

        def mkcol *args
            # mkcol w/ body is unsupported
            halt 415 if request.content_length
            halt 415 if request.media_type

            # conflict if already exists
            halt 405 unless resource_repo.for_path(request.path_info).empty?

            # fetch the parent collection
            # conflict if the parent doesn't exist (or isn't a collection)
            name, parent_coll = resource_repo.parent_for_path(request.path_info)
            parent            = parent_coll.first

            halt 409 if     parent.nil?
            halt 409 unless parent[:is_coll]

            # otherwise, insert!
            resource_repo.resources.insert(pid: parent[:id], path: name, is_coll: true)
            halt 201
        end

        def head *args
            get *args # sets headers and throws
            nil       # but don't include a body in head requests
        end

        def get *args
            resource = resource_repo.for_path(request.path_info).first

            halt 404 if resource.nil?
            halt 202 if resource[:is_coll]

            if resource[:mime]
                response.headers.merge!("Content-Type" => resource[:mime])
            end

            resource[:content]
        end

        def post *args
            halt 405 # method not supported
        end

        def put *args
            resource_id = resource_repo.for_path(request.path_info).select(:id).get(:id)
            if resource_id
                resource_repo.resources
                    .where(id: resource_id)
                    .update(mime: request.content_type, content: request.body)

                halt 302, "Location" => request.path_info
            else
                # no content already here, get the parent id
                req_path, parent_path = parse_paths(request.path_info)
                parent_id             = resource_repo.for_path(parent_path).select(:id).get(:id)
                halt 404 if parent_id.nil?

                len    = Integer(request.content_length)
                buffer = request.body.read(len)

                resource_repo.resources.insert(pid: parent_id, path: req_path, mime: request.content_type, content: buffer)

                response.status = 201
                if request.content_type
                    response.headers.merge!("Content-Type" => request.content_type)
                end

                buffer
            end
        end

        def delete *args
            res_id = resource_repo.for_path(request.path_info).select(:id).get(:id)
            halt 404 if res_id.nil?

            resource_repo.resources.where(id: res_id).delete
            halt 201
        end

    end
end