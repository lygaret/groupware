# frozen_string_literal: true

require "nokogiri"

require "dav/repos/paths"
require "dav/controllers/base_controller"

module Dav
  module Controllers
    # controller for plain WebDAV resources, without special semantics.
    class Collection < BaseController

      include System::Import[
        "dav.repos.paths",
        "dav.repos.resources",
        "dav.repos.properties",
        "logger"
      ]

      DAV_NSDECL     = { d: "DAV:" }.freeze
      DAV_LOCKSCOPES = %w[exclusive shared].freeze
      DAV_LOCKTYPES  = %w[write].freeze

      OPTIONS_SUPPORTED_METHODS = %w[
        OPTIONS HEAD GET PUT DELETE
        MKCOL COPY MOVE LOCK UNLOCK
        PROPFIND PROPPATCH
      ].freeze

      # TODO: cors? anything else?
      OPTIONS_DEFAULT_HEADERS = {
        "Allow" => OPTIONS_SUPPORTED_METHODS.join(",").freeze
      }.freeze

      # TODO: support range header
      GET_DEFAULT_HEADERS = {
        "Accept-Ranges" => "none"
      }.freeze

      # OPTIONS http method
      def options(*)
        response.headers.merge!(OPTIONS_DEFAULT_HEADERS)
        complete 202
      end

      # HEAD http method is just a get, but the router will discard the body
      # @see Router#respond
      def head(path:, ppath:) = get(path:, ppath:)

      # GET http method
      # returns the resource at a given path
      def get(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        complete! 204 if path.collection?

        resource = resources.at_path(pid: path.id)
        complete! 204 if resource.nil? # no content at path!

        # resource exists, merge into response
        response.headers.merge! GET_DEFAULT_HEADERS
        response.headers.merge! resource.http_headers

        # lazy reader will be discarded by the router for HEAD requests
        response.body = resources.content_for(rid: resource.id)
        complete 200
      end

      # MKCOL http (webdav) method
      # creates a collection at the given path
      def mkcol(path:, ppath:)
        invalid! "mkcol w/ body is unsupported", status: 415 if request.media_type
        invalid! "mkcol w/ body is unsupported", status: 415 if request.content_length

        # path itself can't already exist
        invalid! "path already exists", status: 405 unless path.nil?

        # intermediate collections must already exist
        # but at the root, there's no parent, so ppath may still be nil below!
        missing_inter = request.path.dirname != "" && ppath.nil?
        invalid! "intermediate paths must exist", status: 409 if missing_inter

        # root cant' be locked
        validate_lock!(path: ppath) unless ppath.nil?

        paths.transaction do
          pid   = ppath&.id
          path  = request.path.basename
          props = [{ xmlel: "resourcetype", content: "<collection/>" }]

          pid = paths.insert(pid:, path:, ctype: "collection")
          properties.set_properties(pid:, props:, user: false)
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

        paths.delete(id: path.id)
        complete 204 # no content
      end

      # COPY http (webdav) method
      # clones the subtree at the given path to a different parent
      def copy(path:, ppath:) = copy_move path:, ppath:, move: false

      # MOVE http (webdav) method
      # moves the subtree at the given path to a different parent
      def move(path:, ppath:) = copy_move path:, ppath:, move: true

      # PROPFIND http (webdav) method
      # returns properties set on the given resource, possibly recursively
      def propfind(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        invalid! "expected xml body", status: 415 unless request.xml_body?(allow_nil: true)

        # newer rfc allows not supporting infinite propfind
        depth = request.dav_depth
        invalid! "Depth: infinity is not supported", status: 409 if depth == :infinity

        # handle the command from the body
        case propfind_command(request.xml_body)
        in :allprop
          propfind_response_for(path:, depth:)
        in :propname
          propfind_response_for(path:, depth:, shallow: true)
        in [:prop, prop]
          filters = prop.element_children.map { propfind_to_filter _1 }
          propfind_response_for(path:, depth:, filters:)
        else
          invalid! "invalid xml!", status: 400
        end
      end

      # PROPPATCH http (webdav) method
      # set/remove properties on the given resource, in document order
      def proppatch(path:, ppath:)
        invalid! "not found", status: 404 if path.nil?
        invalid! "expected xml body", status: 415 unless request.xml_body?(allow_nil: true)

        validate_lock!(path:)

        # handle the commands from the body; it's important that they're handled in order
        proppatch_each_command(request.xml_body) do |command, props|
          case command
          when :set
            properties.set_xml_properties(pid: path.id, user: true, props:)
          when :remove
            properties.remove_xml_properties(pid: path.id, user: true, props:)
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

        paths.clear_lock(token: request.dav_locktoken)
        complete 204
      end

      private

      # insert a resource at the parent path
      def put_insert(ppath:)
        invalid! "parent must be a collection", status: 409 unless ppath&.collection?
        validate_lock!(path: ppath)

        paths.transaction do
          pid  = ppath.id
          path = request.path.basename

          # the new path is the parent of the resource
          pid = paths.insert(pid:, path:, ctype: nil)

          display  = CGI.unescape(path)
          type     = request.dav_content_type
          length   = request.dav_content_length
          lang     = request.get_header("content-language")
          content  = request.md5_body.read(length)
          etag     = request.md5_body.hexdigest

          # insert the resource at that path
          resources.upsert_at(pid:, display:, type:, lang:, length:, content:, etag:, creating: true)
        end

        complete 201
      end

      # update a resource at the given path
      def put_update(path:)
        invalid "not found", status: 404 if path.nil?
        validate_lock!(path:)

        pid     = path.id
        display = CGI.unescape(path.path)
        type    = request.dav_content_type
        length  = request.dav_content_length
        lang    = request.get_header("content-language")
        content = request.md5_body.read(length)
        etag    = request.md5_body.hexdigest

        resources.upsert_at(pid:, display:, type:, lang:, length:, content:, etag:, creating: false)
        complete 204
      end

      # copy or move a tree from one path to another
      def copy_move(path:, ppath:, move:)
        invalid! "not found", status: 404 if path.nil?

        paths.transaction do
          dest  = request.dav_destination
          pdest = paths.at_path(dest.dirname)
          invalid! "destination root must be a collection", status: 409 unless pdest&.collection?

          extant = paths.at_path(dest.to_s)
          unless extant.nil?
            invalid! "destination must not already exist", status: 412 unless request.dav_overwrite?

            validate_lock!(path: extant)
            paths.delete(id: extant.id)
          end

          validate_lock!(path: pdest)
          if move
            validate_lock!(path:)
            paths.move_tree(id: path.id, dpid: pdest.id, dpath: dest.basename)
          else
            paths.clone_tree(id: path.id, dpid: pdest.id, dpath: dest.basename)
          end

          status = extant.nil? ? 201 : 204
          complete status
        end
      end

      # --- properties

      # given an xml doc from a propfind, parse out the command to run
      # @param doc [Nokogiri::XML::Document] the request xml body to parse
      # @return [Array<[Symbol, XMLElement>]] a pair of the command, and the args to the command handler
      def propfind_command(doc)
        return [:allprop] if doc.nil? # empty doc is an allprop command

        root = doc.at_css("d|propfind:only-child", DAV_NSDECL)
        invalid! "expected propfind in xml root", status: 415 if root.nil?

        allprop = root.at_css("d|allprop", DAV_NSDECL)
        return :allprop unless allprop.nil?

        propname = root.at_css("d|propname", DAV_NSDECL)
        return :propname unless propname.nil?

        prop = root.at_css("d|prop", DAV_NSDECL)
        return [:prop, prop] unless prop.nil?

        invalid! "expected one of prop, propname, allprop in xml root", status: 414
      end

      # parse the given element to get a property filter
      def propfind_to_filter(elem)
        badname = elem.namespace.nil? && elem.name.include?(":")
        invalid! "invalid xmlns/name #{elem.name}, xmlns=''", status: 400 if badname

        { xmlns: elem.namespace&.href || "", xmlel: elem.name }
      end

      # respond with the specific properties on the given path
      def propfind_response_for(path:, depth:, shallow: false, filters: [])
        pathprops = properties.at_path(pid: path.id, depth:, filters:)
        response.xml_body do |xml|
          render_prop_multistatus(xml:, pathprops:, expected: filters, shallow:)
        end

        complete 207
      end

      # parse the property update xml doc, and yield commands to the caller
      def proppatch_each_command(doc)
        update_el = doc&.at_css("d|propertyupdate:only-child", DAV_NSDECL)
        invalid! "expected propertyupdate in xml root", status: 415 if update_el.nil?

        update_el.element_children.each do |child_el|
          props = child_el.css("> d|prop > *", DAV_NSDECL)

          case child_el
          in { name: "set", namespace: { href: "DAV:" }}
            yield :set, props
          in { name: "remove", namespace: { href: "DAV:" }}
            yield :remove, props
          else
            invalid! "expected only <set> and <remove>!", status: 400
          end
        end
      end

      # given some props, render a multistatus propstat response
      def render_prop_multistatus(xml:, pathprops:, expected: [], shallow:)
        xml["d"].multistatus("xmlns:d" => "DAV:") do
          pathprops.each do |fullpath, props|
            xml["d"].response do
              xml["d"].href fullpath

              # track missing items _per path_
              missing = expected.dup

              # found keys
              unless props.empty?
                render_propstat(xml:, status: "200 OK", props:) do |row|
                  render_proprow(xml:, row:, shallow:)

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
      def render_proprow(xml:, row:, shallow:)
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

      # --- locks

      # grant a lock on tha path
      def lock_grant(path:, ppath:)
        invalid! status: 412 unless check_ifstate(path:)

        lockinfo = request.xml_body.css("> d|lockinfo:only-child", DAV_NSDECL)
        scope    = lockinfo.at_css("> d|lockscope", DAV_NSDECL).element_children.first&.name
        type     = lockinfo.at_css("> d|locktype", DAV_NSDECL).element_children.first&.name
        owner    = lockinfo.at_css("> d|owner", DAV_NSDECL)&.children&.to_xml

        pid      = path&.id
        deep     = request.dav_depth == :infinity
        timeout  = request.dav_timeout

        # basic input validation
        invalid! "locktype must be supported" unless DAV_LOCKTYPES.include? type
        invalid! "lockscope must be exclusive/shared" unless DAV_LOCKSCOPES.include? scope

        # lock can create an empty, preemptively locked path, but intermediates must exist
        invalid! "intermediate paths must exist!", status: 409 if pid.nil? && ppath.nil?

        # lock scope must be compatible with any extant locks
        invalid! "already locked, lockscope", status: 423 unless paths.lock_allowed?(lids: path&.plockids, scope:)

        status = 200
        token  = paths.transaction do
          # lock puts an empty resource to unknown paths, preemptively locked
          if pid.nil?
            status = 201
            pid    = paths.insert(pid: ppath.id, path: request.path.basename)
          end

          logger.info("granting lock", owner:, scope:, type:, timeout:)
          paths.grant_lock(pid:, deep:, type:, scope:, owner:, timeout:)
        end

        lock = paths.lock_info(token:)
        failure! "somehow our lock doesnt exist!?" unless lock

        response.headers.merge! "lock-token" => lock[:id].token
        response.xml_body do |xml|
          xml["d"].prop("xmlns:d" => "DAV:") do
            render_lockdiscovery(xml:, lock:, root: request.path_info)
          end
        end

        complete status
      end

      # refresh the lock on a path
      def lock_refresh(path:, ppath:)
        invalid! "not found!", status: 404 unless path
        invalid! "cant refresh an unlocked lock", status: 412 unless path.plockids

        validate_lock!(path:)

        token = request.dav_submitted_tokens&.first
        invalid! "no lock token submitted!", status: 412 unless token

        timeout = request.dav_timeout
        res     = paths.refresh_lock(token:, timeout:)
        invalid! "couldn't refresh lock from token", status: 400 unless res

        lock = paths.lock_info(token:)
        failure! "somehow our lock doesnt exist!?" unless lock

        response.headers.merge! "lock-token" => lock[:id].token
        response.xml_body do |xml|
          xml["d"].prop("xmlns:d" => "DAV:") do
            render_lockdiscovery(xml:, lock:, root: request.path_info)
          end
        end

        complete 200
      end

      # ensures that the If: header and lock state of the given path makes sense.
      # @param path [PathMethods] the path to check locks
      # @param direct [bool] if true, doesn't consider inherited locks
      def validate_lock!(path:, direct: false)
        invalid! status: 412 unless check_ifstate(path:)
        invalid! status: 423 unless check_lock(path:, direct:)
      end

      # take a current path as context, and verify that the submitted request
      # has presented the correct lock token to be able to use the lock.
      def check_lock(path:, direct: false)
        lids = direct ? path&.lockids : path&.plockids
        return true unless lids

        # good if there's any intersection of submitted and current
        request.dav_submitted_tokens.intersect? lids
      end

      # validate the ifstate struct, using the current path as context for untagged clauses
      # @param ifstate [IfState] the ifstate to check; if nil, returns true.
      # @param context_path [Hash] the pathrow to use in untagged clauses
      # @return [Bool]
      def check_ifstate(path:)
        return true if request.dav_ifstate.nil?

        request.dav_ifstate.clauses.any? do |clause|
          rpath = path
          unless clause.uri.nil?
            # a non-nil clause uri means we're checking against the path from the header
            uri   = request.normalize_dav_path(clause.uri)
            rpath = uri && paths.at_path(uri)
          end

          clause.predicates.all? do |pred|
            case pred
            when Dav::IfState::TokenPredicate
              toggle_bool(rpath&.plockids&.include?(pred.token), pred.inv)

            when Dav::IfState::EtagPredicate
              property = rpath && properties.find_at_path(pid: rpath.id, xmlel: "getetag")
              toggle_bool(property && (pred.etag == property[:content].to_s), pred.inv)
            end
          end
        end
      end

      # possibly invert the value of the given boolean.
      # just XOR, but makes more sense with this name in context.
      #
      # @example
      #   toggle_bool(true, true) #=> false
      #   toggle_bool(true, false) #=> true
      #   toggle_bool(false, true) #=> true
      #   toggle_bool(false, false) #=> false
      def toggle_bool(bool, toggle)
        !toggle ^ !bool # coerce to bool first, numbers are xor'd bitwise, !x^!y == x^y
      end

      # given an xml builder and a lock, render a <DAV:lockdiscovery> block
      def render_lockdiscovery(xml:, root:, lock:)
        xml["d"].lockdiscovery do
          xml["d"].activelock do
            xml["d"].locktype  { xml["d"].send lock[:type] }
            xml["d"].lockscope { xml["d"].send lock[:scope] }
            xml["d"].locktoken { xml["d"].href lock[:id].token }
            xml["d"].lockroot  { xml["d"].href root }

            depth = lock[:deep] ? "infinity" : 0
            xml["d"].depth depth

            owner = Nokogiri::XML.fragment(lock[:owner]).to_xml
            xml["d"].owner owner

            timeout = lock[:remaining].then { "Second-#{_1}" }
            xml["d"].timeout timeout
          end
        end
      end

    end
  end
end
