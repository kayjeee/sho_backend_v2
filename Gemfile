source "https://rubygems.org"

# Core Framework
gem "rails", "~> 8.0.2"
gem "puma", ">= 5.0"

# Asset & Frontend
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

# API & CORS
gem "rack-cors"

# Database
gem "mongoid"

# Authentication & Security
gem "jwt"

# Serialization
gem "active_model_serializers"

# Background / Realtime (Action Cable)
gem "redis", "~> 5.0"

# File Processing
gem "roo"
# csv is part of Ruby stdlib — no need to include it as a gem

# Performance
gem "bootsnap", require: false
gem "thruster", require: false

# Deployment
gem "kamal", require: false

# Platform-specific
gem "tzinfo-data", platforms: [:jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end