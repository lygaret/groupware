# frozen_string_literal: true

Sequel.migration do
  up do
    run_file "./views/paths_extra_01.sql"
  end

  down do
    drop_view :paths_extra
  end
end
