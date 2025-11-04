require_relative "boot"

# --- Load only the frameworks you need ---
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
#require "active_job/railtie"
require "active_model/railtie"
# ❌ No ActionCable
# ❌ No Sprockets / assets

# --- Load gems from Gemfile ---
Bundler.require(*Rails.groups)

# --- Load .env automatically if dotenv-rails is in Gemfile ---
require "dotenv-rails"
Dotenv.load(File.expand_path("../.env", __dir__))

module ShoBackendV2
  class Application < Rails::Application
    # --- Initialize Rails defaults ---
    config.load_defaults 8.0

    # --- API-only mode ---
    config.api_only = true

    # --- Mongoid setup ---
    config.generators do |g|
      g.orm :mongoid
      g.test_framework nil
      g.assets false
      g.helper false
      g.view_specs false
      g.controller_specs false
      g.routing_specs false
    end

    # --- Skip ActiveRecord if accidentally referenced ---
    if ENV["SKIP_DB"]
      module ActiveRecord
        class Base
          def self.establish_connection(*); end
        end
      end
    end

    # --- Autoload app/lib for custom modules ---
    config.autoload_paths << Rails.root.join("app", "lib")
    config.eager_load_paths << Rails.root.join("app", "lib")

    # --- Time zone & I18n ---
    config.time_zone = "Pretoria"
    config.i18n.default_locale = :en
    config.i18n.available_locales = [:en]
    config.i18n.fallbacks = true

    # --- Background jobs ---
    config.active_job.queue_adapter = :solid_queue

    # --- Caching ---
    config.cache_store = :memory_store

    # --- Security ---
    config.force_ssl = true

    # --- Logging ---
    config.log_tags = [:request_id]
    logger           = Logger.new($stdout)
    logger.formatter = Logger::Formatter.new
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
    config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym

    # --- Default URL options for mailers & other services ---
    config.action_mailer.default_url_options = {
      host: ENV.fetch("APP_HOST", "example.com"),
      protocol: "https"
    }
  end
end
