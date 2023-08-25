require "time"
require "nokogiri"
require "pp"

require "ioutil/md5_reader"
require "http/method_router"
require "http/request_path"

module Dav
  class Router < Http::MethodRouter

    include App::Import[
      "logger",
      "repositories.resources"
    ]

    attr_reader :request_path

    DAV_NSDECL = { d: "DAV:" }
    DAV_DEPTHS = %w[infinity 0 1]

    OPTIONS_SUPPORTED_METHODS = %w[
      OPTIONS HEAD GET PUT DELETE
      MKCOL COPY MOVE LOCK UNLOCK 
      PROPFIND PROPPATCH
    ].join ","

    def before_req
      super

      @request_path = Http::RequestPath.from_path @request.path_info
    end

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
        "Content-Length" => resource[:length].to_s,
        "Content-Type"   => resource[:type],
        "Last-Modified"  => resource[:updated_at] || resource[:created_at],
        "ETag"           => resource[:etag]
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
      body = IOUtil::MD5Reader.new request.body
      content = body.read(len) # hashes as a side effect

      resources.update(
        id: resource_id,
        type: request.content_type,
        length: len,
        content: content,
        etag: body.hash
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
        len  = Integer(request.content_length)
        body = IOUtil::MD5Reader.new request.body
        content = body.read(len) # hashes as a side effect

        resources.insert(
          pid: parent[:id], 
          path: request_path.name,
          type: request.content_type,
          length: len,
          content: content,
          etag: body.hash
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

    def proppatch *args
      resource_id = resources.at_path(request_path.path).get(:id)
      halt 404 if resource_id.nil?

      # body must be declared xml (missing content type means we have to guess)
      halt 415 unless request.content_type.nil? || request.content_type =~ /(text|application)\/xml/

      # body must be a valid propertyupdate element
      body   = request.body.gets
      doc    = Nokogiri::XML.parse body rescue halt(400, $!.to_s)
      update = doc.at_css("d|propertyupdate:only-child", DAV_NSDECL)
      halt 415 if update.nil?

      # handle the (set|remove)+ in the update children in order
      resources.connection.transaction do
        update.element_children.each do |child|
          case [child.name, child.namespace]
          in "set", { href: "DAV:" }
            child.css("> d|prop > *", DAV_NSDECL).each do |prop|
              xmlns = prop.namespace&.href || ""
              xmlel = prop.name
              value = prop.content

              resources
                .connection[:properties_user]
                .insert_conflict(:replace)
                .insert(rid: resource_id, xmlns:, xmlel:, value:)
            end
          in "remove", { href: "DAV:" }
            scope = resources.connection[:properties_user]
            child.css("> d|prop > *", DAV_NSDECL).each do |prop|
              scope.or(rid: resource_id, xmlns: prop.namespace.href, xmlel: prop.name)
            end

            scope.delete
            halt 204
          else

            halt 400
          end
        end
      end

      halt 201
    end

    def propfind *args
      resource_id = resources.at_path(request_path.path).get(:id)
      halt 404 if resource_id.nil?

      depth = request.get_header("HTTP_DEPTH") || "infinity"
      halt 400 unless DAV_DEPTHS.include? depth
      depth = depth == "infinity" ? 1000000 : depth.to_i

      # an empty body means allprop
      body = request.body.gets
      if (body.nil? || body == "")
        return propfind_allprop(resource_id, depth:, root: nil)
      end

      # body must be declared xml (missing content type means we have to guess)
      halt 415 unless request.content_type.nil? || request.content_type =~ /(text|application)\/xml/

      # otherwise, it must be a well-formed xml doc
      # which has a <DAV:propfind> element at the root
      doc  = Nokogiri::XML.parse body rescue halt(400, $!.to_s)
      root = doc.at_css("d|propfind:only-child", DAV_NSDECL)
      halt 400 if root.nil?

      allprop = root.at_css("d|allprop", DAV_NSDECL)
      unless allprop.nil?
        return propfind_allprop(resource_id, depth:, root:)
      end

      propname = root.at_css("d|propname", DAV_NSDECL)
      unless propname.nil?
        return propfind_propname(resource_id, depth:, root:, names: propname)
      end

      prop     = root.at_css("d|prop", DAV_NSDECL)
      unless prop.nil?
        return propfind_prop(resource_id, depth:, root:, props: prop)
      end

      # not sure what to do with this
      halt 400
    end

    def propfind_allprop(rid, depth:, root:, **opts)
      scope = resources.with_descendants(rid, depth:)
                .join(resources.connection[:properties_all], rid: :id)



      # separate by paths
      values = Hash.new { |h, k| h[k] = [] }
      scope.each do |row|
        values[row[:fullpath]] << row
      end 

      # combine into the allprop response
      builder   = Nokogiri::XML::Builder.new do |xml|
        xml.multistatus(xmlns: "DAV:") {
          values.each do |path, data|
            xml.response {
              xml.href path
              xml.propstat {
                xml.prop do
                  data.each do |row|
                    frag = Nokogiri::XML.fragment %Q[<#{row[:xmlel]} xmlns="#{row[:xmlns]}">#{row[:value]}</#{row[:xmlel]}>]
                    xml << frag.to_xml
                  end
                end
                xml.status "HTTP/1.1 200 OK"
              }
            }
          end
        }
      end

      puts builder.to_xml
      halt 207, builder.to_xml
    end

    def propfind_propname rid, depth:, root:, names:
      scope = resources.with_descendants(rid, depth:)
                .join(resources.connection[:properties_all], rid: :id)
                .select_all

      # separate by paths
      values = Hash.new { |h, k| h[k] = [] }
      scope.each do |row|
        values[row[:fullpath]] << row
      end 

      # combine into the allprop response
      builder   = Nokogiri::XML::Builder.new do |xml|
        xml.multistatus(xmlns: "DAV:") {
          values.each do |path, data|
            xml.response {
              xml.href path
              xml.propstat {
                xml.prop do
                  data.each do |row|
                    frag = Nokogiri::XML.fragment %Q[<#{row[:xmlel]} xmlns="#{row[:xmlns]}" />]
                    xml << frag.to_xml
                  end
                end
                xml.status "HTTP/1.1 200 OK"
              }
            }
          end
        }
      end

      puts builder.to_xml
      halt 207, builder.to_xml
    end

    def propfind_prop rid, depth:, root:, props:
      scope = resources.with_descendants(rid, depth:)
                .join(resources.connection[:properties_all], rid: :id)
                .select_all
                .where(Sequel.lit("1 = 0"))

      debugger
      props.element_children.each do |prop|
        scope = scope.or(xmlns: prop.namespace&.href, xmlel: prop.name)
      end

      # separate by paths
      values = Hash.new { |h, k| h[k] = [] }
      scope.each do |row|
        values[row[:fullpath]] << row
      end 

      # combine into the allprop response
      builder   = Nokogiri::XML::Builder.new do |xml|
        xml.multistatus(xmlns: "DAV:") {
          values.each do |path, data|
            xml.response {
              xml.href path
              xml.propstat {
                xml.prop do
                  data.each do |row|
                    frag = Nokogiri::XML.fragment %Q[<#{row[:xmlel]} xmlns="#{row[:xmlns]}" />]
                    xml << frag.to_xml
                  end
                end
                xml.status "HTTP/1.1 200 OK"
              }
            }
          end
        }
      end

      puts builder.to_xml
      halt 207, builder.to_xml
    end

    def propget *args
      halt 500
    end

    def propmove *args
      halt 500
    end

  end
end
