require "active_support/core_ext/integer/time"

Rails.application.configure do
  # -----------------------------------------
  # Core Rails Production Settings
  # -----------------------------------------

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # -----------------------------------------
  # Static Files
  # -----------------------------------------

  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}"
  }

  # -----------------------------------------
  # Logging
  # -----------------------------------------

  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent Railway health checks from flooding logs
  config.silence_healthcheck_path = "/up"

  # -----------------------------------------
  # SSL / Proxy (Railway compatible)
  # -----------------------------------------

  config.assume_ssl = false
  config.force_ssl = false

  # -----------------------------------------
  # Caching / Jobs
  # -----------------------------------------

  config.cache_store = :memory_store
  config.active_job.queue_adapter = :async

  # -----------------------------------------
  # I18n
  # -----------------------------------------

  config.i18n.fallbacks = true

  # -----------------------------------------
  # Mailer (FIXED)
  # -----------------------------------------

  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost"),
    protocol: "https"
  }

  # -----------------------------------------
  # Host Authorization (🚨 CRITICAL FOR RAILWAY)
  # -----------------------------------------

  # Allow Railway internal health checks
  config.hosts.clear

  # Optional: restrict to your domain (recommended later)
  # config.hosts << "schoolheadoffice.com"
  # config.hosts << "www.schoolheadoffice.com"
  # config.hosts << /.*\.railway\.app/

end
