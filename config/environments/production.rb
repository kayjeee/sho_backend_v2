require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Enable caching for API responses if needed.
  config.action_controller.perform_caching = true

  # Cache assets or public files for far-future expiry.
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.year.to_i}" }

  # Force all access to the app over SSL.
  config.assume_ssl = true
  config.force_ssl = true

  # Use STDOUT logging (important for Docker/Render/Vercel).
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(Logger.new(STDOUT))
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Silence health check logs.
  config.silence_healthcheck_path = "/up"

  # Don’t log deprecations in production.
  config.active_support.report_deprecations = false

  # Use in-memory cache store or Redis (optional).
  config.cache_store = :memory_store

  # ActiveJob (background jobs) – disable or configure your own.
  config.active_job.queue_adapter = :async

  # Configure default URL options for mailers (if used).
  config.action_mailer.default_url_options = { host: "example.com" }
  # config.action_mailer.raise_delivery_errors = false

  # Fallbacks for I18n.
  config.i18n.fallbacks = true

  # ✅ Disable ActiveRecord (you’re using Mongoid instead)
  config.active_record = nil

  # ✅ Disable ActiveStorage completely
  if config.respond_to?(:active_storage)
    config.active_storage.draw_routes = false
  end

  # Host protection (optional)
  # config.hosts << "your-production-domain.com"
end
