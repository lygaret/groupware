# frozen_string_literal: true

Sequel.migration do
  up do
    create_table :owners do
      column :id,   :text, primary_key: true, null: false
      column :name, :text
    end

    # todo, is deleting paths when the user's deleted a bad idea?
    # this will likely involve the controllers doing resource cleanup anyway
    alter_table :paths do
      add_foreign_key :oid, :owners, key: :id, type: :text, null: true, on_delete: :cascade
    end

    # add the oid to the paths_extra view
    run_file "./views/paths_extra_02.sql"
  end

  down do
    run_file "./views/paths_extra_01.sql"

    alter_table :paths do
      drop_column :oid
    end

    drop_table :owners
  end
end
