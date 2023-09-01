# frozen_string_literal: true

env = ENV["APP_ENV"] ||= "development"

require "bundler"
Bundler.setup(:default, env)

require "dotenv"
Dotenv.load(".env", ".env.#{env}")

require "debug" if env != "production"
