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
          content  = Nokogiri::XML.fragment(prop.children, DAV_NSDECL).to_xml

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
            contents.each do |path, data|
              xml["d"].response {
                xml["d"].href path
                xml["d"].propstat {
                  xml["d"].prop do
                    data.each do |row|
                      attrs = Hash.new(JSON.load(row[:xmlattrs]))
                      if row[:xmlns] == "DAV:"
                        xml["d"].send(row[:xmlel], **attrs) do 
                          xml.send(:insert, Nokogiri::XML.fragment(row[:content]))
                        end
                      else
                        attrs.merge! xmlns: row[:xmlns]
                        xml.send(row[:xmlel], **attrs) do 
                          xml.send(:insert, Nokogiri::XML.fragment(row[:content]))
                        end
                      end
                    end
                  end
                  xml["d"].status "HTTP/1.1 200 OK"
                }
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
            contents.each do |path, data|
              xml["d"].response {
                xml["d"].href path
                xml["d"].propstat {
                  xml["d"].prop do
                    data.each do |row|
                      if row[:xmlns] == "DAV:"
                        xml["d"].send(row[:xmlel])
                      else
                        xml.send(row[:xmlel], xmlns: row[:xmlns])
                      end
                    end
                  end
                  xml["d"].status "HTTP/1.1 200 OK"
                }
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
        desc  = resources.with_descendants(rid, depth:)
        scope = desc 
                  .join_table(:left_outer, :properties_all, rid: :id)
                  .select_all(:properties_all).select_append(:fullpath)
                  .where(Sequel.lit("1 = 0"))

        expected = []
        props.element_children.each do |prop|
          expected << prop
          scope = scope.or(xmlns: prop.namespace&.href || "", xmlel: prop.name)
        end

        # need a path element in contents for every child
        contents = Hash.new { |h,k| h[k] = [] }
        scope.select(:fullpath).each do |row|
          contents[row[:fullpath]] = []
        end

        # add the properties we've found
        scope.each do |row|
          contents[row[:fullpath]] << row
        end 

        # combine into the allprop response
        builder   = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") {
            contents.each do |path, data|
              missing = expected.dup

              xml["d"].response {
                xml["d"].href path

                # found keys
                unless data.empty?
                  xml["d"].propstat {
                    xml["d"].prop {
                      data.each do |row|
                        # remove matched properties from the set
                        # track missing so we can report 404 on the others
                        missing.reject! do |p| 
                          ((p.namespace&.href == row[:xmlns]) || ("" == row[:xmlns])) && (p.name == row[:xmlel])
                        end

                        attrs = Hash.new(JSON.load(row[:xmlattrs]))
                        if row[:xmlns] == "DAV:"
                          xml["d"].send(row[:xmlel], **attrs) {
                            xml.send(:insert, Nokogiri::XML.fragment(row[:content]))
                          }
                        else
                          attrs.merge!(xmlns: row[:xmlns])
                          xml.send(row[:xmlel], **attrs) {
                            xml.send(:insert, Nokogiri::XML.fragment(row[:content]))
                          }
                        end
                      end
                    }
                    xml["d"].status "HTTP/1.1 200 OK"
                  }
                end

                unless missing.empty?
                  xml["d"].propstat {
                    xml["d"].prop {
                      missing.each do |prop|
                        xml.send(prop.name, xmlns: prop.namespace&.href || "")
                      end
                    }
                    xml["d"].status "HTTP/1.1 404 Not Found"
                  }
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


    end
  end
end