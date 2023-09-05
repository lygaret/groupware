-- containers for paths/resources we need to clone
-- we need to generate new ids for the clones, and maintain the mapping from id->newid

create table if not exists temp.path_clones
  (id TEXT, pid TEXT, newid TEXT, newpid TEXT, newpath TEXT);

create table if not exists temp.resource_clones
  (id TEXT, newid TEXT, newpid TEXT);

-- collect new ids for the subtree we're cloning
with recursive descendants (id, pid, path, newid) as (
  select paths.id, paths.pid, paths.path, uuid() as newid
    from paths where id = <%= source_id %>
  union
  select paths.id, paths.pid, paths.path, uuid() as newid
    from paths
    join descendants on descendants.id = paths.pid
)
insert into temp.path_clones
  select
    child.id,
    child.pid,
    child.newid,
    coalesce(parent.newid, <%= dest_pid %>),
    case when parent.id is null
      then <%= dest_path %>
      else child.path
    end
  from      descendants child
  left join descendants parent on parent.id = child.pid;

-- same for resources; get id->newid mappings
insert into temp.resource_clones
  select
    res.id,
    uuid() as newid,
    pc.newid as newpid
  from resources res
  join temp.path_clones pc on res.pid = pc.id;

-- now we explicitly clone, path down, using the mappings for new pids

insert into paths
  select
    targets.newid,
    targets.newpid,
    targets.newpath,
    orig.ctype
  from temp.path_clones targets
  join paths orig on orig.id = targets.id;

insert into resources
  select
    targets.newid,
    targets.newpid,
    res.type,
    res.length,
    res.content,
    res.etag,
    datetime('now'),
    null
  from temp.resource_clones targets
  join resources res on res.id = targets.id;

insert into properties
  select
    null,
    targets.newid, -- pid, path property
    null,
    prop.user,
    prop.xmlns,
    prop.xmlel,
    prop.xmlattrs,
    prop.content
  from properties prop
  join temp.path_clones targets on prop.pid = targets.id;

insert into properties
  select
    null,
    null,
    targets.newid, -- rid, resource property
    prop.user,
    prop.xmlns,
    prop.xmlel,
    prop.xmlattrs,
    prop.content
  from properties prop
  join temp.resource_clones targets on prop.pid = targets.id;

-- and cleanup, in case we somehow multiplexed the temp table
drop table temp.path_clones;
drop table temp.resource_clones;
