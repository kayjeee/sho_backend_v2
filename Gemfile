source "https://rubygems.org"

# Rails framework
gem "rails", "~> 8.0.2"
gem "propshaft"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

gem 'rack-cors'

# Database
gem "mongoid"

# Authentication & Security
gem 'jwt'

# Serialization
gem 'active_model_serializers'

# File Processing
gem 'roo'
gem 'csv'

# Performance
gem "bootsnap", require: false
gem "thruster", require: false

# Deployment
gem "kamal", require: false

# Platform specific
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
