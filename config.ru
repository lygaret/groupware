require          "nancy/base"
require_relative "system/app"

App::Container.finalize!

class DAVResource
    def initialize(repo, parent, name)
        @repo   = repo
        @parent = parent
        @name   = name
    end

    def collection?    = false
    def exists?        = false
    def parent_exists? = true
end

class DAVCollection < DAVResource
    def collection? = true

    def mkcol name
        @repo.make_collection name
    end
end

class DAVRepository
    def initialize
        @collections = {}
    end

    def resource_at path
        case path 
        in ""
            DAVCollection.new self, nil, path
        else
            @collections[path]
        end
    end

    def make_collection fullpath
        @collections[fullpath] = DAVCollection.new self, nil, fullpath
    end
end

# class DAVApp < Tribe::DAV::Router

#     def initialize backend
#         super(backend)
#     end

#     # 9.3 MKCOL Method
#     # MKCOL creates a new collection resource at the location specified by the Request-URI. If the Request-URI is already mapped to a resource, then the MKCOL MUST fail. 
#     # During MKCOL processing, a server MUST make the Request-URI an internal member of its parent collection, unless the Request-URI is "/". If no such ancestor exists, 
#     # the method MUST fail. When the MKCOL operation creates a new collection resource, all ancestors MUST already exist, or the method MUST fail with a 409 (Conflict)
#     # status code. For example, if a request to create collection /a/b/c/d/ is made, and /a/b/c/ does not exist, the request must fail.
#     #
#     # When MKCOL is invoked without a request body, the newly created collection SHOULD have no members.
#     #
#     # A MKCOL request message may contain a message body. The precise behavior of a MKCOL request when the body is present is undefined, but limited to creating 
#     # collections, members of a collection, bodies of members, and properties on the collections or members. If the server receives a MKCOL request entity type it does 
#     # not support or understand, it MUST respond with a 415 (Unsupported Media Type) status code. If the server decides to reject the request based on the presence of 
#     # an entity or the type of an entity, it should use the 415 (Unsupported Media Type) status code.
#     #
#     # This method is idempotent, but not safe (see Section 9.1 of [RFC2616]). Responses to this method MUST NOT be cached.

#     # 9.3.1. MKCOL Status Codes
#     # In addition to the general status codes possible, the following status codes have specific applicability to MKCOL:
#     # - 201 (Created) - The collection was created.
#     # - 403 (Forbidden) - This indicates at least one of two conditions: 1) the server does not allow the creation of collections at the given location in its URL 
#     #     namespace, or 2) the parent collection of the Request-URI exists but cannot accept members.
#     # - 405 (Method Not Allowed) - MKCOL can only be executed on an unmapped URL.
#     # - 409 (Conflict) - A collection cannot be made at the Request-URI until one or more intermediate collections have been created. The server MUST NOT create those 
#     #     intermediate collections automatically.
#     # - 415 (Unsupported Media Type) - The server does not support the request body type (although bodies are legal on MKCOL requests, since this specification doesn't 
#     #     define any, the server is likely not to support any given body type).
#     # - 507 (Insufficient Storage) - The resource does not have sufficient space to record the state of the resource after the execution of this method.

#     def mkcol root
#         debugger
#         halt 409 if     root.exists?
#         halt 409 unless root.parent.exists? 
#         halt 415 unless @request.content_length == 0
#         halt 415 unless @request.media_type.nil?

#         root.parent.mkcol @request.path_info.split('/').last
#         halt 201
#     end

#     def propfind root
#         debugger
#         halt 404
#     end

# end

class MainApp < Nancy::Base
    get("/")    { "hi from nancy" }
    # map("/dav") { run DAVApp.new DAVRepository.new }
end

run MainApp.new