# frozen_string_literal: true

require "repos/base_repo"

module Repos
  # the data access layer to the path storage
  class Paths < BaseRepo

    include System::Import["db.connection"]

    def paths      = connection[:paths]
    def paths_full = connection[:paths_full]

    def at_path(path)
      filtered_paths = paths_full.where(fullpath: path)
      paths.join(filtered_paths, id: :id)
    end

    def insert(pid:, path:, ctype: nil)
      results = paths.returning(:id).insert(id: SQL.uuid, pid:, path:, ctype:)
      results&.first&.[](:id)
    end

    def delete(id:)
      # cascades in the database to delete children
      paths.where(id:).delete
    end

    # moves the tree at spid now be under dpid, changing it's name
    # simply repoints the spid parent pointer
    def move_tree(id:, dpid:, dpath:)
      paths.where(id:).update(pid: dpid, path: dpath)
    end

    # causes the path tree at spid to be cloned into the path tree at dpid,
    # with the path component dpath;
    #
    # this is a deep clone, including resources at those paths.
    def clone_tree(id:, dpid:, dpath:)
      connection.run <<~SQL
        create table if not exists temp.clone_targets
          (sourceid TEXT, id TEXT, pid TEXT, newid TEXT, newpid TEXT, newpath TEXT);

        -- select the subtree, along with new ids
        with recursive descendants (id, pid, path, newid) as (
          select paths.id, paths.pid, paths.path, uuid() as newid
            from paths where id = '#{id}'
          union
          select paths.id, paths.pid, paths.path, uuid() as newid
            from paths
            join descendants on descendants.id = paths.pid
        )

        -- update each descendant with the new pid from their parent
        -- and save off the mappings, so we can clone everything afterwards
        insert into temp.clone_targets
          select
            '#{id}',
            child.id,
            child.pid,
            child.newid,
            coalesce(parent.newid, '#{dpid}'),
            case when parent.id is null
              then '#{dpath}'
              else child.path
            end
          from      descendants child
          left join descendants parent on parent.id = child.pid;

        -- now we explicitly clone, using the mappings for new pids
        insert into paths
          select
            targets.newid,
            targets.newpid,
            targets.newpath,
            orig.ctype
          from temp.clone_targets targets
          join paths orig on targets.sourceid = '#{id}' and orig.id = targets.id;

        -- and resources
        insert into resources
          select
            uuid(),
            targets.newid as pid,
            res.type,
            res.length,
            res.content,
            res.etag,
            datetime('now'),
            null
          from resources res
          join temp.clone_targets targets on targets.sourceid = '#{id}' and targets.id = res.pid;

        -- and cleanup, in case we somehow multiplexed the temp table
        delete from temp.clone_targets
          where sourceid = '#{id}';
      SQL
    end

  end
end
