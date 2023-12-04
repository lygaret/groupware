# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> 3.1"

gem "dotenv", "~> 2.8"
gem "ougai", "~> 2.0"
gem "rack", "~> 3.0", github: "rack/rack", branch: "main"
gem "rackup", "~> 2"

gem "nokogiri", "~> 1.15"
gem "parslet", "~> 2.0"
gem "string-inquirer", "~> 0", git: "https://gist.github.com/117441fc5236de9f7d54b76894d69dec.git"

gem "sequel", "~> 5.75"
gem "sqlite3", "~> 1.6"

gem "dry-events", "~> 1.0"
gem "dry-monitor", "~> 1.0"
gem "dry-struct", "~> 1.0"
gem "dry-system", "~> 1.0"
gem "dry-types", "~> 1.0"
gem "zeitwerk", "~> 2.6"

group :test do
  gem "rspec", "~> 3.12"
end

group :development, :test do
  gem "amazing_print", "~> 1"
  gem "debug", "~> 1"
  gem "rake", "~> 13.0"

  gem "rubocop", "~> 1.56"
  gem "rubocop-rake", "~> 0.6"
  gem "rubocop-rspec", "~> 2.24"
  gem "rubocop-sequel", "~> 0.3"

  gem "redcarpet", "~> 3.6"
  gem "yard", "~> 0.9.34"
  gem "yard-junk", "~> 0.0.9"
end
