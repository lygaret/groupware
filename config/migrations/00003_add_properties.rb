# frozen_string_literal: true

Sequel.migration do
  up do
    run <<~SQL
      CREATE TABLE properties (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        pid        TEXT NULL references paths(id) ON DELETE CASCADE,
        rid        TEXT NULL references resources(id) ON DELETE CASCADE,
        user       INTEGER DEFAULT 1, -- true if user property, false if server managed

        xmlns      TEXT NOT NULL, -- the xml namespace owning this property
        xmlel      TEXT NOT NULL, -- the xml element name of this property
        xmlattrs   BLOB NOT NULL, -- the xml attributes, serialized as json array [["attr1","value"], ["attr2","value"]]
        content    BLOB NOT NULL, -- the inner content of the property

        -- we can only have one owner
        CHECK ((pid IS NULL AND rid IS NOT NULL)
            OR (pid IS NOT NULL AND rid IS NULL))
      );

      CREATE        INDEX properties_rid_idx on properties (rid);
      CREATE UNIQUE INDEX properties_ridfqn_idx on properties (rid, xmlns, xmlel);

      CREATE        INDEX properties_pid_idx on properties (pid);
      CREATE UNIQUE INDEX properties_pidfqn_idx on properties (pid, xmlns, xmlel);
    SQL
  end

  down do
    drop_table :properties
  end
end
