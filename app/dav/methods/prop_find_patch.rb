require 'json'
require 'benchmark'

module Dav
  module Methods
    module PropFindPatchMethods

      # RFC 2518, Section 8.1 - PROPFIND Method
      # http://www.webdav.org/specs/rfc2518.html#METHOD_PROPFIND
      def propfind *args
        resource_id = resources.id_at_path(request.path)
        halt 404 if resource_id.nil?

        # we can't handle infinity directly, rather we pass a big-ol value
        depth = request.dav_depth
        depth = 100_000_000 if depth == :infinity

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
        resource_id = resources.id_at_path(request.path)
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
              # set each property given
              child.css("> d|prop > *", DAV_NSDECL).each do |prop|
                resources.set_property(resource_id, prop:)
              end
            in {name: "remove", namespace: {href: "DAV:"}}
              # remove each property given
              child.css("> d|prop > *", DAV_NSDECL).each do |prop|
                resources.remove_property(resource_id, xmlns: prop.namespace.href, xmlel: prop.name)
              end
            else
              # bad request if we got action other than set/remove
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

      def propfind_allprop(rid, depth:, root:, **opts)
        # Hash<:fullpath, [property rows]>
        properties = resources.fetch_properties(rid, depth:)

        # combine into the allprop response
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            properties.each do |path, props|
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
        # Hash<:fullpath, [property rows]>
        properties = resources.fetch_properties(rid, depth:)

        # combine into the allprop response
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            properties.each do |path, props|
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
        # collect the expected children
        filters = props.element_children.map do |p|
          { xmlns: p.namespace&.href || "", xmlel: p.name }
        end

        # filter to just the requested properties children
        properties = resources.fetch_properties(rid, depth:, filters:)

        # combine into the allprop response
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            properties.each do |path, props|
              missing = filters.dup

              xml["d"].response {
                xml["d"].href path

                # found keys
                unless props.empty?
                  render_propstat(xml:, status: "200 OK", props:) do |row|
                    render_row xml:, row:, shallow: false

                    # track missing so we can report 404 on the others
                    missing.reject! do |prop|
                      row[:xmlns] == prop[:xmlns] && row[:xmlel] == prop[:xmlel]
                    end
                  end
                end

                # data still in missing is reported 404
                unless missing.empty?
                  render_propstat(xml:, status: "404 Not Found", props: missing) do |prop|
                    xml.send(prop[:xmlel], xmlns: prop[:xmlns])
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