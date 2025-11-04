source "https://rubygems.org"

ruby "~> 3.3.0"

# add this instead
gem 'pg', '~> 1.5'
# --- Core Rails ---
gem "rails", "~> 8.0.2"
gem "puma", ">= 5.0"

gem 'jsonapi-serializer'


# --- MongoDB ---
gem "mongoid", "~> 9.0" # Ensure Mongoid version compatible with Rails 8
gem "bson_ext", require: false # Optional: improves BSON performance

# --- Authentication / Authorization ---
gem "jwt", "~> 2.9" # Fixes missing jwt error for Auth0 integration
gem "rack-cors" # For handling CORS in API mode

# --- Asset & Frontend ---
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

# --- JSON & APIs ---
gem "jbuilder"

# --- Background Jobs & Caching ---
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# --- Performance / Boot ---
gem "bootsnap", require: false

# --- Deployment ---
gem "kamal", require: false
gem "thruster", require: false

# --- Platform Compatibility ---
gem "tzinfo-data", platforms: %i[ windows jruby ]

# --- Development & Test ---
group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
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
