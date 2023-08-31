Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE properties_user (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        rid        TEXT NOT NULL references resources(id) ON DELETE CASCADE,
        xmlns      TEXT NOT NULL, -- the xml namespace owning this property
        xmlel      TEXT NOT NULL, -- the xml element name of this property
        xmlattrs   BLOB NOT NULL, -- the xml attributes, serialized as json array [["attr","content"]]
        content    BLOB NOT NULL  -- the inner content of the property
      );

      CREATE        INDEX properties_rid_idx on properties_user (rid);
      CREATE UNIQUE INDEX properties_ridfqn_idx on properties_user (rid, xmlns, xmlel);

      CREATE VIEW properties_dav AS
        WITH property_cte (rid, xmlns, xmlel, xmlattrs, content) AS (
                SELECT res.id, 'DAV:', 'creationdate', '[]', res.created_at FROM resources res
          UNION SELECT res.id, 'DAV:', 'displayname', '[]', unescape_url(res.path) FROM resources res        -- todo
          UNION SELECT res.id, 'DAV:', 'resourcetype', '[]', CASE WHEN res.colltype IS NOT NULL THEN ('<' || res.colltype || '/>') ELSE NULL END FROM resources res
          UNION SELECT res.id, 'DAV:', 'getcontentlanguage', '[]', 'en-US' FROM resources res  -- todo
          UNION SELECT res.id, 'DAV:', 'getcontentlength', '[]', res.length FROM resources res 
          UNION SELECT res.id, 'DAV:', 'getcontenttype', '[]', res.type FROM resources res
          UNION SELECT res.id, 'DAV:', 'getetag', '[]', res.etag FROM resources res
          UNION SELECT res.id, 'DAV:', 'getlastmodified', '[]', COALESCE(res.updated_at, res.created_at) FROM resources res
        ) 
        SELECT
          NULL as id,
          prop.rid,
          prop.xmlns, 
          prop.xmlel,
          prop.xmlattrs,
          prop.content
        FROM
          resources res
          JOIN  property_cte prop ON prop.rid = res.id;

        CREATE VIEW properties_all AS
          SELECT * FROM properties_user
          UNION
          SELECT * FROM properties_dav;
    SQL
  end

  down do
    drop_view :properties_all
    drop_view :properties_dav
    drop_table :properties_user
  end
end
