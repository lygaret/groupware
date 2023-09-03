# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> 3.1"

gem "dotenv", "~> 2.8"
gem "rack", "~> 3.0", github: "rack/rack", branch: "main"
gem "rackup", "~> 2"

gem "sequel", "~> 5.72"
gem "sqlite3", "~> 1.6"

gem "nokogiri", "~> 1.15"
gem "string-inquirer", "~> 0", git: "https://gist.github.com/117441fc5236de9f7d54b76894d69dec.git"

gem "dry-events", "~> 1.0"
gem "dry-monitor", "~> 1.0"
gem "dry-system", "~> 1.0"
gem "dry-types", "~> 1.0"
gem "zeitwerk", "~> 2.6"

group :test do
  gem "rspec", "~> 3.12"
end

group :development, :test do
  gem "debug", "~> 1"
  gem "rake", "~> 13.0"

  gem "rubocop", "~> 1.56"
  gem "rubocop-rake", "~> 0.6"
  gem "rubocop-rspec", "~> 2.23"
  gem "rubocop-sequel", "~> 0.3"
end
