module Repositories
  class Resources
    include App::Import["db.connection"]

    def resources = connection[:resources]

    def properties = connection[:properties]

    COL_ID = Sequel[:resource_paths][:id]
    COL_FULLPATH = Sequel[:resource_paths][:fullpath]

    UUID_FUN = Sequel.function(:uuid)
    NOW_FUN = Sequel.lit("datetime('now')")

    def id_at_path path
      connection[:resource_paths]
        .where(path: path&.chomp("/"))
        .get(:id)
    end

    def at_path path
      return connection[:resource_ephemeral_root] if path == ""

      pathid =
        connection[:resource_paths]
          .where(path: path&.chomp("/"))
          .select(:id)

      connection[:resources].where(id: pathid)
    end

    def with_descendants(rid, depth:)
      tree_descendants_cte(rid, depth)
        .join(:resources, id: :id)
        .select_all(:resources)
        .select_append(:fullpath, :depth)
    end

    def move_tree source_id, dest_id, name
      resources
        .where(id: source_id)
        .update(pid: dest_id, path: name, updated_at: NOW_FUN)
    end

    def clone_tree source_id, dest_id, name
      # TODO: figure out param binding in this
      # - string substitution in sql is bad, mkay
      # - naive attempt causes "invalid bind param" errors
      connection.run <<~SQL
        -- since we need to insert into multiple tables,
        -- we need to record the old/new mappings; srcid is to avoid collisions on this table

        create temp table if not exists clone_targets 
          (srcid TEXT, newid TEXT, newpid TEXT, newpath TEXT, oldid TEXT);

        -- get descendants of the given source

        with recursive cte_descendants as (
            -- base - root of the branch to copy (renamed)
            select uuid() as newid, resources.*
            from resources where id = '#{source_id}'
            union
            -- recursive - children of the previously selected nodes
            select uuid() as newid, resources.*
            from resources
            join cte_descendants as c on resources.pid = c.id
        ),

        -- now, since we've recorded the original id/pid and have the new uuid,
        -- we can join and use the correct new id for the parent relationship
        -- if new pid is null (from left join), it's the top-level, and it gets set to the destination

        cte_fixed_pids as (
            select
                coalesce(parent.newid, '#{dest_id}') as newpid,
                case when parent.id is null 
                    then '#{name}'
                    else child.path 
                end as newpath,
                child.*
            from      cte_descendants child
            left join cte_descendants parent on child.pid = parent.id
        )

        -- record the src/target mappings

        insert into temp.clone_targets (srcid, newid, newpid, newpath, oldid)
        select 
          '#{source_id}',
          fixed.newid, 
          fixed.newpid, 
          fixed.newpath, 
          fixed.id
        from cte_fixed_pids fixed;

        -- and then clone the resources and user properties

        insert into resources (id, pid, path, coll, type, length, content, etag, created_at, updated_at)
        select
          fixed.newid,
          fixed.newpid,
          fixed.newpath,
          res.coll,
          res.type,
          res.length,
          res.content,
          res.etag,
          datetime('now'),
          null
        from temp.clone_targets fixed
        join resources res on fixed.srcid = '#{source_id}' and fixed.oldid = res.id;

        insert into properties_user (rid, xmlns, xmlel, xmlattrs, content)
        select
          fixed.newid,
          prop.xmlns,
          prop.xmlel,
          prop.xmlattrs,
          prop.content
        from temp.clone_targets fixed
        join properties_user prop on fixed.srcid = '#{source_id}' and fixed.oldid = prop.rid;

        delete from temp.clone_targets
        where srcid = '#{source_id}';
      SQL
    end

    def insert pid:, path:, **data
      data = blobify_data_content data
      opts = data.merge(
        id: UUID_FUN,
        pid: pid,
        path: path,
        created_at: NOW_FUN
      )

      resources.insert(**opts)
    end

    def update id:, **data
      data = blobify_data_content data
      opts = data.merge(
        updated_at: NOW_FUN
      )

      resources.where(id: id).update(**opts)
    end

    def delete id:
      # cascades in the database to delete children
      resources.where(id: id).delete
    end

    def set_property rid, prop:
      xmlns = prop.namespace&.href || ""
      xmlel = prop.name
      xmlattrs = JSON.dump prop.attributes.to_a
      content = Nokogiri::XML.fragment(prop.children).to_xml

      connection[:properties_user]
        .insert_conflict(:replace)
        .insert(rid:, xmlns:, xmlel:, xmlattrs:, content:)
    end

    def remove_property rid, xmlns:, xmlel:
      connection[:properties_user].where(rid:, xmlns:, xmlel:).delete
    end

    def fetch_properties rid, depth:, filters: nil
      join = :properties_all
      if filters
        join = connection[:properties_all].where(false)
        join = filters.reduce(join) do |scope, filter|
          scope.or(filter)
        end
      end

      scope =
        with_descendants(rid, depth:)
          .join_table(:left_outer, join, {rid: :id}, table_alias: :properties_all)
          .select_all(:properties_all)
          .select_append(:fullpath)

      scope.each_with_object({}) do |row, results|
        results[row[:fullpath]] ||= []
        next if row[:rid].nil? # nil object from left outer join

        results[row[:fullpath]] << row
      end
    end

    private

    def blobify_data_content data
      return data unless data.key? :content
      return data if data[:content].nil?

      data.merge(content: Sequel::SQL::Blob.new(data[:content]))
    end

    def tree_descendants_cte root_id, depth
      connection[:desc].with_recursive(:desc,
        connection[:resource_paths]
          .select(:id, :path, Sequel[0].as(:depth))
          .where(id: root_id),
        connection[:resources]
          .select(
            Sequel[:resources][:id],
            Sequel[:desc][:fullpath] + "/" + Sequel[:resources][:path],
            Sequel[:desc][:depth] + 1
          )
          .where(Sequel[:depth] < depth)
          .join(:desc, id: :pid),
        args: [:id, :fullpath, :depth])
        .select_all(:desc)
    end
  end
end
