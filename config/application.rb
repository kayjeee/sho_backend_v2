require_relative "boot"

# ✅ Load only frameworks you actually use — skip ActiveRecord & Sprockets
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
# ❌ No ActiveRecord (using Mongoid)
# ❌ No ActionCable or Sprockets

Bundler.require(*Rails.groups)

module ShoBackendV2
  class Application < Rails::Application
    # Initialize configuration defaults for Rails 8.0
    config.load_defaults 8.0

    # ✅ API-only mode — lightweight, no views or assets
    config.api_only = true

    # ✅ Use Mongoid instead of ActiveRecord
    config.generators do |g|
      g.orm :mongoid
      g.test_framework nil
      g.assets false
      g.helper false
    end

    # ✅ Skip DB initialization in environments where it’s not needed (e.g. Docker build)
    if ENV["SKIP_DB"]
      module ActiveRecord
        class Base
          def self.establish_connection(*); end
        end
      end
    end

    # ✅ Autoload from lib/, ignoring non-code folders
    config.autoload_lib(ignore: %w[assets tasks])

    # ✅ Time zone & I18n defaults
    config.time_zone = "Pretoria"
    config.i18n.available_locales = [:en]
    config.i18n.default_locale = :en

    # ✅ Background job adapter (SolidQueue or Sidekiq)
    config.active_job.queue_adapter = :solid_queue

    # ✅ Cache store (use Redis or memory depending on env)
    config.cache_store = :memory_store

    # ✅ Force SSL for security
    config.force_ssl = true

    # ✅ Logging setup — works perfectly in Docker & Render
    config.log_tags = [:request_id]
    logger = Logger.new($stdout)
    logger.formatter = Logger::Formatter.new
    config.logger = ActiveSupport::TaggedLogging.new(logger)
    config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

    # ✅ Default host for URL generation
    config.action_mailer.default_url_options = {
      host: ENV.fetch("APP_HOST", "example.com"),
      protocol: "https"
    }
  end
end
