Sequel.migration do
  
  up do
    drop_view :properties_dav
  end

  down do
    run <<~SQL
      CREATE VIEW properties_dav AS
        WITH property_cte (rid, xmlns, xmlel, xmlattrs, content) AS (
                SELECT res.id, 'DAV:', 'creationdate', '[]', res.created_at FROM resources res
          UNION SELECT res.id, 'DAV:', 'displayname', '[]', unescape_url(res.path) FROM resources res        -- todo
          UNION SELECT res.id, 'DAV:', 'resourcetype', '[]', CASE res.coll WHEN 1 THEN '<collection/>' ELSE NULL END FROM resources res
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
    SQL
  end

end