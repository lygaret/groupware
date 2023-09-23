# frozen_string_literal: true

Sequel.migration do
  up do
    drop_view :paths_full
  end

  down do
    run_file "./views/paths_full_01.sql"
  end
end
