Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE properties_sys (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        rid        TEXT NOT NULL references resources(id) ON DELETE CASCADE,
        xmlns      TEXT NOT NULL, -- the xml namespace owning this property
        xmlel      TEXT NOT NULL, -- the xml element name of this property
        xmlattrs   BLOB NOT NULL, -- the xml attributes, serialized as json array [["attr","content"]]
        content    BLOB           -- the inner content of the property (can be null on collections)
      );

      CREATE        INDEX properties_sys_rid_idx on properties_sys (rid);
      CREATE UNIQUE INDEX properties_sys_ridfqn_idx on properties_sys (rid, xmlns, xmlel);

      DROP VIEW properties_all;
      CREATE VIEW properties_all AS
        SELECT * FROM properties_user
        UNION
        SELECT * FROM properties_sys;

      CREATE TRIGGER IF NOT EXISTS properties_sys_insert_resources 
      AFTER INSERT ON resources BEGIN
        INSERT OR REPLACE 
        INTO properties_sys (rid, xmlns, xmlel, xmlattrs, content)
        VALUES 
          (NEW.id, 'DAV:', 'creationdate',       '[]', NEW.created_at),
          (NEW.id, 'DAV:', 'displayname',        '[]', unescape_url(NEW.path)),
          (NEW.id, 'DAV:', 'resourcetype',       '[]', CASE NEW.coll WHEN 1 THEN '<collection/>' ELSE NULL END),
          (NEW.id, 'DAV:', 'getcontentlanguage', '[]', 'en-US'), -- todo
          (NEW.id, 'DAV:', 'getcontentlength',   '[]', NEW.length),
          (NEW.id, 'DAV:', 'getcontenttype',     '[]', NEW.type),
          (NEW.id, 'DAV:', 'getetag',            '[]', NEW.etag),
          (NEW.id, 'DAV:', 'getlastmodified',    '[]', COALESCE(NEW.updated_at, NEW.created_at));
      END;

      CREATE TRIGGER IF NOT EXISTS properties_sys_update_resources 
      AFTER UPDATE ON resources BEGIN
        INSERT OR REPLACE 
        INTO properties_sys (rid, xmlns, xmlel, xmlattrs, content)
        VALUES 
          (NEW.id, 'DAV:', 'creationdate',       '[]', NEW.created_at),
          (NEW.id, 'DAV:', 'displayname',        '[]', unescape_url(NEW.path)),
          (NEW.id, 'DAV:', 'resourcetype',       '[]', CASE NEW.coll WHEN 1 THEN '<collection/>' ELSE NULL END),
          (NEW.id, 'DAV:', 'getcontentlanguage', '[]', 'en-US'), -- todo
          (NEW.id, 'DAV:', 'getcontentlength',   '[]', NEW.length),
          (NEW.id, 'DAV:', 'getcontenttype',     '[]', NEW.type),
          (NEW.id, 'DAV:', 'getetag',            '[]', NEW.etag),
          (NEW.id, 'DAV:', 'getlastmodified',    '[]', COALESCE(NEW.updated_at, NEW.created_at));
      END;

      INSERT INTO properties_sys (rid, xmlns, xmlel, xmlattrs, content) 
        SELECT rid, xmlns, xmlel, xmlattrs, content FROM properties_dav;
    SQL
  end

  down do
    run <<~SQL
      DROP VIEW properties_all;
      CREATE VIEW properties_all AS
        SELECT * FROM properties_user
        UNION
        SELECT * FROM properties_dav;

      DROP TABLE properties_sys;
    SQL
  end
end
