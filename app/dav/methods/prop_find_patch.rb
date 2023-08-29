require 'json'

module Dav
  module Methods
    module PropFindPatchMethods

      # RFC 2518, Section 8.1 - PROPFIND Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_PROPFIND
      def propfind *args
        resource_id = resources.at_path(request_path.path).get(:id)
        halt 404 if resource_id.nil?

        # depth tells us how deep to go
        depth = request_depth

        # an empty body means allprop
        body = request.body.gets
        if (body.nil? || body == "")
          return propfind_allprop(resource_id, depth:, root: nil)
        end

        # body must be a valid propfind element
        doc  = fetch_request_xml! body
        root = doc.at_css("d|propfind:only-child", DAV_NSDECL)
        halt 400 if root.nil?

        # look for the operation type, and dispatch
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

        # no valid operation in the body?
        halt 400
      end

      # RFC 2518, Section 8.2 - PROPPATCH Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_PROPPATCH
      def proppatch *args
        resource_id = resources.at_path(request_path.path).get(:id)
        halt 404 if resource_id.nil?

        # body must be a valid propertyupdate element
        doc    = fetch_request_xml!
        update = doc.at_css("d|propertyupdate:only-child", DAV_NSDECL)
        halt 415 if update.nil?

        # handle the (set|remove)+ in the update children in order
        # this is a SPEC ENFORCED n+1 QUERY, because we need to handle a set/remove pair on the same resource
        resources.connection.transaction do
          update.element_children.each do |child|
            case child
            in {name: "set", namespace: {href: "DAV:"}}
              proppatch_set resource_id, child
            in {name: "remove", namespace: {href: "DAV:"}}
              proppatch_remove resource_id, child
            else
              # bad document if we got a request other than set/remove
              halt 400
            end
          end
        end

        halt 201
      end

      private

      def fetch_request_xml!(body = nil)
        # body must be declared xml (missing content type means we have to guess)
        halt 415 unless request.content_type.nil? || request.content_type =~ /(text|application)\/xml/

        body ||= request.body.gets
        Nokogiri::XML.parse body rescue halt(400, $!.to_s)
      end

      def request_depth
        depth = request.get_header("HTTP_DEPTH") || "infinity"
        halt 400 unless DAV_DEPTHS.include? depth

        depth == "infinity" ? 1000000 : depth.to_i
      end

      def proppatch_set resource_id, setel
        setel.css("> d|prop > *", DAV_NSDECL).each do |prop|
          xmlns    = prop.namespace&.href || ""
          xmlel    = prop.name
          xmlattrs = JSON.dump prop.attributes.to_a
          content  = Nokogiri::XML.fragment(prop.children).to_xml

          resources
            .connection[:properties_user]
            .insert_conflict(:replace)
            .insert(rid: resource_id, xmlns:, xmlel:, xmlattrs:, content:)
        end
      end

      def proppatch_remove resource_id, remel
        # reduce over the props to collect a bunch of OR statements, so we can delete everything in one go
        # the where(false) is necessary to get the ors to compose, as the default is where(true)
        scope = resources.connection[:properties_user].where(false)
        scope = remel.css("> d|prop > *", DAV_NSDECL).reduce(scope) do |scope, prop|
          scope.or(rid: resource_id, xmlns: prop.namespace.href, xmlel: prop.name)
        end

        scope.delete
      end

      def propfind_allprop(rid, depth:, root:, **opts)
        scope = resources.with_descendants(rid, depth:)
                  .join_table(:left_outer, :properties_all, rid: :id)
                  .select_all(:properties_all).select_append(:fullpath)

        # separate by paths
        contents = Hash.new { |h, k| h[k] = [] }
        scope.each do |row|
          contents[row[:fullpath]] << row
        end 

        # combine into the allprop response
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            contents.each do |path, props|
              xml["d"].response {
                xml["d"].href path
                render_propstat(xml:, status: "200 OK", props:) do |row|
                  render_row xml:, row:, shallow: false
                end
              }
            end
          }
        end

        # puts "PROPFIND ALLPROP depth:#{depth}"
        # puts root
        # puts "resp------------------"
        # puts builder.to_xml
        # puts "----------------------"

        halt 207, builder.to_xml
      end

      def propfind_propname rid, depth:, root:, names:
        scope = resources.with_descendants(rid, depth:)
                  .join_table(:left_outer, :properties_all, rid: :id)
                  .select_all(:properties_all).select_append(:fullpath)

        # separate by paths
        contents = Hash.new { |h, k| h[k] = [] }
        scope.each do |row|
          contents[row[:fullpath]] << row
        end 

        # combine into the allprop response
        builder   = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            contents.each do |path, props|
              xml["d"].response {
                xml["d"].href path
                render_propstat(xml:, status: "200 OK", props:) do |row|
                  render_row xml:, row:, shallow: true
                end
              }
            end
          }
        end

        # puts "PROPFIND NAMES (depth #{depth})"
        # puts names
        # puts "resp------------------"
        # puts builder.to_xml
        # puts "----------------------"

        halt 207, builder.to_xml
      end

      def propfind_prop rid, depth:, root:, props:
        desc    = resources.with_descendants(rid, depth:)
        dbprops = resources.connection[:properties_all].where(false)

        # collect the expected children
        # reducing the dbprops scope with `ORs` along the way
        expected = []
        props.element_children.each do |prop|
          expected << prop
          dbprops = dbprops.or(xmlns: prop.namespace&.href || "", xmlel: prop.name)
        end

        # scope now is a left outer join (all the resources, prop cols are nil if missing)
        scope = desc
          .join_table(:left_outer, dbprops, { rid: :id }, table_alias: :props)
          .select_all(:props).select_append(:fullpath)

        # need a path element in contents for every child
        contents = Hash.new { |h,k| h[k] = [] }
        scope.each do |row|
          contents[row[:fullpath]] ||= []
          next if row[:xmlel].nil? # no property found

          contents[row[:fullpath]] << row
        end 

        # combine into the allprop response
        builder   = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            contents.each do |path, props|
              missing = expected.dup

              xml["d"].response {
                xml["d"].href path

                # found keys
                unless props.empty?
                  render_propstat(xml:, status: "200 OK", props:) do |row|
                    render_row xml:, row:, shallow: false

                    # track missing so we can report 404 on the others
                    missing.reject! do |p|
                      nsmatch = row[:xmlns] == "" || row[:xmlns] == p.namespace&.href
                      nsmatch && (p.name == row[:xmlel])
                    end
                  end
                end

                # data still in missing is reported 404
                unless missing.empty?
                  render_propstat(xml:, status: "404 Not Found", props: missing) do |prop|
                    xml.send(prop.name, xmlns: prop.namespace&.href || "")
                  end
                end
              }
            end
          }
        end

        # puts "PROPFIND PROPS (depth #{depth})"
        # puts props
        # puts "resp------------------"
        # puts builder.to_xml
        # puts "----------------------"

        halt 207, builder.to_xml
      end

      def render_propstat xml:, status:, props:
        xml["d"].propstat {
          xml["d"].status "HTTP/1.1 #{status}"
          xml["d"].prop {
            props.each { |row| yield row }
          }
        }
      end

      def render_row xml:, row:, shallow:
        attrs   = Hash.new(JSON.load(row[:xmlattrs]))
        content = shallow ? nil : ->(_) do 
          xml.send(:insert, Nokogiri::XML.fragment(row[:content]))
        end

        if row[:xmlns] == "DAV:"
          xml["d"].send(row[:xmlel], **attrs, &content)
        else
          attrs.merge! xmlns: row[:xmlns]
          xml.send(row[:xmlel], **attrs, &content)
        end
      end

    end
  end
end