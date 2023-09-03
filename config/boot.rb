# frozen_string_literal: true

env = ENV["APP_ENV"] ||= (ENV["APP_ENV"]&.downcase || "development")

require "bundler"
Bundler.setup(:default, env)

require "dotenv"
Dotenv.load(".env", ".env.#{env}")

require "debug" if env == "development"
