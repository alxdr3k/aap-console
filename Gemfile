source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Solid stack (SQLite-backed cache, queue, cable)
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "bootsnap", require: false
gem "thruster", require: false

# Authentication
gem "omniauth", "~> 2.1"
gem "omniauth-keycloak", "~> 1.4"
gem "omniauth-rails_csrf_protection", "~> 2.0"

# HTTP client for external API calls (Keycloak, Langfuse, Config Server)
gem "faraday", "~> 2.9"
gem "faraday-retry", "~> 2.2"
gem "faraday-net_http", "~> 3.1"

# Thread-safe concurrency primitives for parallel provisioning steps
gem "concurrent-ruby", "~> 1.3"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "rubocop-rails-omakase", require: false

  # TDD
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails", "~> 6.4"
  gem "shoulda-matchers", "~> 6.0"
  gem "faker", "~> 3.3"
end

group :test do
  gem "webmock", "~> 3.23"
  gem "vcr", "~> 6.3"
  gem "simplecov", require: false
end

group :development do
  gem "web-console"
end
