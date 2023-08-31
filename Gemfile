source "https://rubygems.org"

ruby "~> 3.1"

gem "rack", "~> 3.0", github: "rack/rack", branch: "main"
gem "sequel"
gem "sqlite3"
gem "nokogiri"
gem "dotenv"
gem "rake"
gem "zeitwerk"

gem "string-inquirer", "~> 0", git: "https://gist.github.com/117441fc5236de9f7d54b76894d69dec.git"

gem "dry-system"
gem "dry-events"
gem "dry-monitor"
gem "dry-types"

group :test do
  gem "rspec", "~> 3.12"
end

group :development, :test do
  gem "debug"
  gem "rackup"
  gem "standard"
  gem "awesome_print"
end
