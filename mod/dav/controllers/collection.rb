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

      DAV_NSDECL     = { d: "DAV:" }.freeze
      DAV_LOCKSCOPES = %w[exclusive shared].freeze

      OPTIONS_SUPPORTED_METHODS = %w[
        OPTIONS HEAD GET PUT DELETE
        MKCOL COPY MOVE LOCK UNLOCK
        PROPFIND PROPPATCH
      ].join(",").freeze

      # OPTIONS http method
      # - respond with allowed methods
      # - TODO: cors? what else?
      def options(*)
        response["Allow"] = OPTIONS_SUPPORTED_METHODS
        complete 204
      end

      # HEAD http method
      # returns the headers for a resource at a given path, but includes no body
      def head(path:, ppath:)
        get(path:, ppath:, include_body: false)
      end

      # GET http method
      # returns the resource at a given path
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
              "Last-Modified" => Time.at(resource[:updated_at] || resource[:created_at]).rfc2822,
              "ETag" => resource[:etag]
            }
            headers.reject! { _2.nil? }

            response.body = [resource[:content]] if include_body
            response.headers.merge! headers

            complete 200
          end
        end
      end

      # MKCOL http (webdav) method
      # creates a collection at the given path
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

        # root cant' be locked
        validate_lock!(path: ppath) unless ppath.nil?

        paths.transaction do
          pid   = ppath&.[](:id)
          path  = request.path.basename
          props = [{ xmlel: "resourcetype", content: "<collection/>" }]

          pid = paths.insert(pid:, path:, ctype: "collection")
          paths.set_properties(pid:, props:, user: false)
        end

        complete 201 # created
      end

      # PUT http method
      # upserts a resource to the given path
      def put(path:, ppath:)
        if path.nil?
          put_insert(ppath:)
        else
          put_update(path:)
        end
      end

      # DELETE http method
      # recursively deletes a path and it's children
      def delete(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        validate_lock!(path:)

        paths.delete(id: path[:id])
        complete 204 # no content
      end

      # COPY http (webdav) method
      # clones the subtree at the given path to a different parent
      def copy(path:, ppath:)
        copy_move path:, ppath:, move: false
      end

      # MOVE http (webdav) method
      # moves the subtree at the given path to a different parent
      def move(path:, ppath:)
        copy_move path:, ppath:, move: true
      end

      # PROPFIND http (webdav) method
      # returns properties set on the given resource, possibly recursively
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

      # PROPPATCH http (webdav) method
      # set/remove properties on the given resource, in document order
      def proppatch(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        invalid! "expected xml body", status: 415 unless request.xml_body?(allow_nil: true)

        validate_lock!(path:)

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

      def lock(path:, ppath:)
        if request.xml_body?
          lock_grant(path:, ppath:)
        else
          lock_refresh(path:, ppath:)
        end
      end

      def unlock(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        validate_lock!(path:, direct: true)

        paths.send(:locks).where(id: path[:lockid]).delete
        complete 204
      end

      private

      # insert a resource at the parent path
      def put_insert(ppath:)
        invalid! "intermediate path not found", status: 409 if ppath.nil?
        invalid! "parent must be a collection", status: 409 if ppath[:ctype].nil?

        validate_lock!(path: ppath)

        paths.transaction do
          pid  = ppath[:id]
          path = request.path.basename

          # the new path is the parent of the resource
          pid = paths.insert(pid:, path:, ctype: nil)

          display  = CGI.unescape(path)
          type     = request.dav_content_type
          length   = request.dav_content_length
          lang     = request.get_header("content-language")
          content  = request.md5_body.gets
          etag     = request.md5_body.hexdigest

          # insert the resource at that path
          paths.put_resource(pid:, display:, type:, lang:, length:, content:, etag:, creating: true)
        end

        complete 201
      end

      # update a resource at the given path
      def put_update(path:)
        invalid "not found", status: 404 if path.nil?
        validate_lock!(path:)

        pid     = path[:id]
        display = CGI.unescape(path[:path])
        type    = request.dav_content_type
        length  = request.dav_content_length
        lang    = request.get_header("content-language")
        content = request.md5_body.read(length)
        etag    = request.md5_body.hexdigest

        paths.put_resource(pid:, display:, type:, lang:, length:, content:, etag:, creating: false)
        complete 204
      end

      # copy or move a tree from one path to another
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

            validate_lock!(path: extant)
            paths.delete(id: extant[:id])
          end

          validate_lock!(path: pdest)
          if move
            validate_lock!(path:)
            paths.move_tree(id: path[:id], dpid: pdest[:id], dpath: dest.basename)
          else
            paths.clone_tree(id: path[:id], dpid: pdest[:id], dpath: dest.basename)
          end

          status = extant.nil? ? 201 : 204
          complete status
        end
      end

      # return all* properties from the given path
      # if shallow, only return the names
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

      # return the specific properties on the given path
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

      def check_ifstate(path:)
        return true if request.dav_ifstate.nil? # nothing to check

        request.dav_ifstate.clauses.any? do |clause|
          upath =
            if clause.uri.nil?
              path
            else
              uri = clause.uri.dup
              uri.delete_prefix! request.base_url
              uri.delete_prefix! request.script_name

              paths.at_path(uri)
            end

          clause.predicates.all? do |p|
            case p
            when IfState::TokenPredicate
              toggle_bool(upath && (p.token == "urn:uuid:#{upath[:plockid]}?=lock"), p.inv)

            when IfState::EtagPredicate
              resource = upath && paths.resource_at(pid: upath[:id])
              toggle_bool(resource && (p.etag == resource[:etag]), p.inv)
            end
          end
        end
      end

      def validate_lock!(path:, direct: false)
        invalid! status: 412 unless check_ifstate(path:)

        lid = path&.[](direct ? :lockid : :plockid)
        return unless lid

        token = "urn:uuid:#{lid}?=lock"
        invalid! status: 423 unless request.dav_submitted_tokens.include?(token)
      end

      def toggle_bool(bool, toggle) = toggle ? !bool : bool

      # grant a lock on tha path
      def lock_grant(path:, ppath:)
        validate_lock!(path:)

        lockinfo = request.xml_body.css("> d|lockinfo:only-child", DAV_NSDECL)
        scope    = lockinfo.at_css("> d|lockscope", DAV_NSDECL).element_children.first
        type     = lockinfo.at_css("> d|locktype", DAV_NSDECL).element_children.first
        owner    = lockinfo.at_css("> d|owner", DAV_NSDECL)&.children&.to_xml

        invalid! "lockscope must be present" if scope.nil?
        invalid! "lockscope must be in the DAV: namespace" if scope.namespace&.href != "DAV:"
        invalid! "lockscope must be exclusive/shared" unless DAV_LOCKSCOPES.include? scope.name
        invalid! "locktype only supports DAV:write" unless type in { name: "write", namespace: { href: "DAV:" } }

        lid = paths.transaction do
          # lock puts an empty resource to unknown paths, preemptively locked
          pid = path&.[](:id) || begin
            invalid! "intermediate paths must exist!", status: 409 if ppath.nil?
            paths.insert(pid: ppath[:id], path: request.path.basename)
          end

          paths
            .send(:locks)
            .returning(:id)
            .insert(
              id: Sequel.function(:uuid),
              pid:,
              deep: request.dav_depth == :infinity,
              type: type.name,
              scope: scope.name,
              owner:,
              timeout: request.dav_timeout,
              refreshed_at: Time.now.to_i,
              created_at: Time.now.to_i
            )
            .then { _1.first[:id] }
        end

        lock    = paths.send(:locks_live).where(id: lid).first
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].prop("xmlns:d" => "DAV:") do
            xml["d"].lockdiscovery do
              xml["d"].activelock do
                xml["d"].locktype { xml["d"].send(lock[:type]) }
                xml["d"].lockscope { xml["d"].send(lock[:scope]) }
                xml["d"].depth(lock[:deep] ? "infinity" : 0)
                xml["d"].owner Nokogiri::XML.fragment(lock[:owner]).to_xml
                xml["d"].timeout(lock[:remaining].then { "Second-#{_1}" })
                xml["d"].locktoken { xml["d"].href "urn:uuid:#{lid}?=lock" }
                xml["d"].lockroot { xml["d"].href request.path_info }
              end
            end
          end
        end

        response.headers.merge! "lock-token" => "urn:uuid:#{lid}?=lock"
        response.headers.merge! "content-type" => "application/xml"
        response.body = [builder.to_xml]

        complete 200
      end

      # refresh the lock on a path
      def lock_refresh(path:, ppath:)
        invalid! "not found!", status: 404 unless path
        invalid! "cant refresh an unlocked lock", status: 412 unless path[:lockid]

        validate_lock!(path:, direct: true)

        lid  = path[:lockid]
        lock = paths.send(:locks).where(id: lid)
        lock.update(timeout: request.dav_timeout, refreshed_at: Time.now.to_i)

        lock    = paths.send(:locks_live).where(id: lid).first
        builder = Nokogiri::XML::Builder.new do |xml|
          xml["d"].prop("xmlns:d" => "DAV:") do
            xml["d"].lockdiscovery do
              xml["d"].activelock do
                xml["d"].locktype { xml["d"].send(lock[:type]) }
                xml["d"].lockscope { xml["d"].send(lock[:scope]) }
                xml["d"].depth(lock[:deep] ? "infinity" : 0)
                xml["d"].owner Nokogiri::XML.fragment(lock[:owner]).to_xml
                xml["d"].timeout(lock[:remaining].then { "Second-#{_1}" })
                xml["d"].locktoken { xml["d"].href "urn:uuid:#{lid}?=lock" }
                xml["d"].lockroot { xml["d"].href request.path_info }
              end
            end
          end
        end

        response.headers.merge! "lock-token" => "urn:uuid:#{lid}?=lock"
        response.headers.merge! "content-type" => "application/xml"
        response.body = [builder.to_xml]

        complete 200
      end

      # given an xml builder, render a <DAV:propstat> block
      def render_propstat(xml:, status:, props:, &block)
        xml["d"].propstat do
          xml["d"].status "HTTP/1.1 #{status}"
          xml["d"].prop do
            props.each(&block)
          end
        end
      end

      # given an xml builder, render a <DAV:prop> block and it's fragment children
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

    end
  end
end
