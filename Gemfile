source "https://rubygems.org"

# --- Core Framework ---
gem "rails", "~> 8.0.2"
gem "propshaft"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

# --- Database ---
gem "mongoid"

# --- Authentication & Security ---
gem "jwt"
gem "rack-cors"

# --- Serialization ---
gem "active_model_serializers"

# --- File Processing ---
gem "roo"
gem "csv"

# --- Performance & Optimization ---
gem "bootsnap", require: false
gem "thruster", require: false

# --- Deployment ---
gem "kamal", require: false

# --- Platform Specific ---
gem "tzinfo-data", platforms: [:jruby]

# --- Development & Test Environment ---
group :development, :test do
  # Debugging (installed only in dev/test to avoid Docker issues)
  gem "debug", platforms: [:mri]

  # Static analysis & code quality
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

# --- Development Only ---
group :development do
  gem "web-console"
end

# --- Test Only ---
group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
