# Gemfile

source "https://rubygems.org"

ruby "~> 3.2.2"

# --- Core Rails ---
gem "rails", "~> 8.0.2"
gem "puma", ">= 5.0"

# --- MongoDB ---
gem "mongoid", "~> 9.0"          # MongoDB ODM compatible with Rails 8
gem "bson_ext", require: false   # Optional: improves BSON performance

# --- Serialization / API ---
gem "jsonapi-serializer"         # JSON:API serialization
gem "jbuilder"                   # Standard JSON templates (optional)

# --- Authentication / Authorization ---
gem "jwt", "~> 2.9"              # JWT support
gem "rack-cors"                  # Handle CORS in API mode

# --- Background Jobs & Caching ---
gem "solid_queue"                # Queue for background jobs
gem "solid_cache"                # Optional cache store

# --- Performance / Boot ---
gem "bootsnap", require: false   # Speeds up boot time

# --- Deployment Helpers ---
gem "kamal", require: false      # Docker deployment tooling
gem "thruster", require: false   # Optional process management

# --- Platform Compatibility ---
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "pg", "~> 1.5"

# --- Environment Variables ---
group :development, :test do
  gem "dotenv-rails"             # Load .env automatically in dev/test
end

# --- Development & Test ---
group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"               # Interactive console for development
end

group :test do
  gem "capybara"                  # Integration testing
  gem "selenium-webdriver"        # Browser driver for Capybara
end
