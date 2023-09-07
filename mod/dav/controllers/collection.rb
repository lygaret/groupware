# frozen_string_literal: true

require "nokogiri"

require "dav/controllers/base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
    class Collection < BaseController

      include System::Import[
        "repos.paths",
        "logger"
      ]

      DAV_NSDECL = { d: "DAV:" }.freeze

      OPTIONS_SUPPORTED_METHODS = %w[
        OPTIONS HEAD GET PUT DELETE
        MKCOL COPY MOVE LOCK UNLOCK
        PROPFIND PROPPATCH
      ].join(",").freeze

      def options(*)
        response["Allow"] = OPTIONS_SUPPORTED_METHODS
        complete 204
      end

      def head(path:, ppath:)
        get(path:, ppath:, include_body: false)
      end

      def get(path:, ppath:, include_body: true)
        invalid! "not found", status: 404 if path.nil?

        if path[:ctype]
          complete 204 # no content for a collection
        else
          resource = paths.resource_at(pid: path[:id])
          if resource.nil?
            complete 204 # no content at path!
          else
            headers  = {
              "Content-Type" => resource[:type],
              "Content-Length" => resource[:length].to_s,
              "Last-Modified" => resource[:updated_at] || resource[:created_at],
              "ETag" => resource[:etag]
            }
            headers.reject! { _2.nil? }

            response.body = [resource[:content]] if include_body
            response.headers.merge! headers

            complete 200
          end
        end
      end

      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # path itself can't already exist
        invalid! "path already exists", status: 405 unless path.nil?

        # intermediate collections must already exist
        # but at the root, there's no parent
        has_inter   = !ppath.nil?
        has_inter ||= request.path.dirname == ""
        invalid! "intermediate paths must exist", status: 409 unless has_inter

        paths.transaction do
          pid   = ppath&.[](:id)
          path  = request.path.basename
          props = [{ xmlel: "resourcetype", content: "<collection/>" }]

          pid = paths.insert(pid:, path:, ctype: "collection")
          paths.set_properties(pid:, props:, user: false)
        end

        complete 201 # created
      end

      def put(path:, ppath:)
        if path.nil?
          put_insert(ppath:)
        else
          put_update(path:)
        end
      end

      def delete(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?

        paths.delete(id: path[:id])
        complete 204 # no content
      end

      def copy(path:, ppath:) = copy_move path:, ppath:, move: false
      def move(path:, ppath:) = copy_move path:, ppath:, move: true

      def propfind(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        invalid! "expected xml body", status: 415 unless request.xml_body?(allow_nil: true)

        # newer rfc allows not supporting infinite propfind
        depth = request.dav_depth
        invalid! "Depth: infinity is not supported", status: 409 if depth == :infinity

        # an empty body means allprop
        doc = request.xml_body
        return propfind_allprop(path:, depth:, shallow: false) if doc.nil?

        # otherwise, fetch the request type and branch on it
        root = doc.at_css("d|propfind:only-child", DAV_NSDECL)
        invalid! "invalid xml, missing propfind", status: 400 if root.nil?

        allprop = root.at_css("d|allprop", DAV_NSDECL)
        return propfind_allprop(path:, depth:, shallow: false) unless allprop.nil?

        propname = root.at_css("d|propname", DAV_NSDECL)
        return propfind_allprop(path:, depth:, propname:, shallow: true) unless propname.nil?

        prop = root.at_css("d|prop", DAV_NSDECL)
        return propfind_prop(path:, depth:, prop:) unless prop.nil?

        invalid! "expected at least one of <allprop>,<propname>,<prop>", status: 400
      end

      def proppatch(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        invalid! "expected xml body", status: 415 unless request.xml_body?(allow_nil: true)

        doc       = request.xml_body
        update_el = doc.at_css("d|propertyupdate:only-child", DAV_NSDECL)
        invalid! "expected propertyupdate in xml root", status: 415 if update_el.nil?

        paths.transaction do
          update_el.element_children.each do |child_el|
            pid   = path[:id]
            props = child_el.css("> d|prop > *", DAV_NSDECL)

            case child_el
            in { name: "set", namespace: { href: "DAV:" }}
              paths.set_xml_properties(pid:, user: true, props:)
            in {name: "remove", namespace: { href: "DAV:" }}
              paths.remove_xml_properties(pid:, user: true, props:)
            else
              # bad request, not sure what we're doing
              invalid! "expected only <set> and <remove>!", status: 400
            end
          end
        end

        complete 201
      end

      private

      def put_insert(ppath:)
        invalid! "intermediate path not found", status: 409 if ppath.nil?
        invalid! "parent must be a collection", status: 409 if ppath[:ctype].nil?

        paths.transaction do
          pid  = ppath[:id]
          path = request.path.basename

          # the new path is the parent of the resource
          id = paths.insert(pid:, path:, ctype: nil)

          display  = CGI.unescape(path)
          type     = request.dav_content_type
          length   = request.dav_content_length
          lang     = request.get_header("content-language")
          content  = request.md5_body.gets
          etag     = request.md5_body.hexdigest

          # insert the resource at that path
          paths.put_resource(pid: id, display:, type:, lang:, length:, content:, etag:, creating: true)
        end

        complete 201
      end

      def put_update(path:)
        invalid "not found", status: 404 if path.nil?

        display = CGI.unescape(path)
        type    = request.dav_content_type
        length  = request.dav_content_length
        lang    = request.get_header("content-language")
        content = request.md5_body.read(length)
        etag    = request.md5_body.hexdigest

        paths.update_resource(pid: path[:id], display:, type:, lang:, length:, content:, etag:, creating: false)
        complete 204
      end

      def propfind_allprop(path:, depth:, shallow:)
        properties = paths.properties_at(pid: path[:id], depth:)
        builder    = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") do
            properties.each do |fullpath, props|
              xml["d"].response do
                xml["d"].href fullpath
                render_propstat_row(xml:, status: "200 OK", props:) do |row|
                  render_row(xml:, row:, shallow:)
                end
              end
            end
          end
        end

        # puts "PROPFIND ALLPROPS (depth #{depth})"
        # puts properties
        # puts "resp------------------"
        # puts builder.to_xml
        # puts "----------------------"

        response.status          = 207
        response.body            = [builder.to_xml]
        response["Content-Type"] = "application/xml"
        response.finish
      end

      def propfind_prop(path:, depth:, prop:)
        # because we have to report on properties we couldn't find,
        # we need to maintain a set of properties we've matched, vs those expected
        # also use this opportunity to validate for bad namespaces
        expected = prop.element_children.map do |p|
          badname = p.namespace.nil? && p.name.include?(":")
          invalid! "invalid xmlns/name #{p.name}, xmlns=''", status: 400 if badname

          { xmlns: p.namespace&.href || "", xmlel: p.name }
        end

        # we can additionally use the set of expected properties to filter the db query
        properties = paths.properties_at(pid: path[:id], depth:, filters: expected)

        # iterate through properties while building the xml
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].multistatus("xmlns:d" => "DAV:") do
            properties.each do |fullpath, props|
              missing = expected.dup # track missing items _per path_

              xml["d"].response do
                xml["d"].href fullpath

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
              end
            end
          end
        end

        # puts "PROPFIND PROPS (depth #{depth})"
        # puts properties
        # puts "resp------------------"
        # puts builder.to_xml
        # puts "----------------------"

        response.status          = 207
        response.body            = [builder.to_xml]
        response["Content-Type"] = "application/xml"
        response.finish
      end

      def render_propstat(xml:, status:, props:, &block)
        xml["d"].propstat do
          xml["d"].status "HTTP/1.1 #{status}"
          xml["d"].prop do
            props.each(&block)
          end
        end
      end

      def render_row(xml:, row:, shallow:)
        attrs   = Hash.new(JSON.parse(row[:xmlattrs]))
        content =
          if shallow
            nil
          else
            lambda do |_|
              xml.send(:insert, Nokogiri::XML.fragment(row[:content]))
            end
          end

        if row[:xmlns] == "DAV:"
          xml["d"].send(row[:xmlel], **attrs, &content)
        else
          attrs.merge! xmlns: row[:xmlns]
          xml.send(row[:xmlel], **attrs, &content)
        end
      end

      def copy_move(path:, ppath:, move:)
        invalid! "not found", status: 404 if path.nil?

        paths.transaction do
          dest  = request.dav_destination
          pdest = paths.at_path(dest.dirname)

          invalid! "destination root must exist", status: 409           if pdest.nil?
          invalid! "destination root must be a collection", status: 409 if pdest[:ctype].nil?

          extant = paths.at_path(dest.to_s)
          unless extant.nil?
            invalid! "destination must not already exist", status: 412 unless request.dav_overwrite?

            paths.delete(id: extant[:id])
          end

          if move
            paths.move_tree(id: path[:id], dpid: pdest[:id], dpath: dest.basename)
          else
            paths.clone_tree(id: path[:id], dpid: pdest[:id], dpath: dest.basename)
          end

          status = extant.nil? ? 201 : 204
          complete status
        end
      end

    end
  end
end
