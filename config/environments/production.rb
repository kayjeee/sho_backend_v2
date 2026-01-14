require "active_support/core_ext/integer/time"

Rails.application.configure do
  # --- Code loading ---
  config.enable_reloading = false
  config.eager_load = true

  # --- Error reports ---
  config.consider_all_requests_local = false

  # --- Caching ---
  config.action_controller.perform_caching = true
  config.cache_store = :solid_cache_store

  # --- Public file server caching ---
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.year.to_i}"
  }

  # --- SSL ---
# Trust Railway's reverse proxy for HTTPS
# config.assume_ssl = true
# config.force_ssl = true
# config.action_dispatch.trusted_proxies = [
 #  IPAddr.new("0.0.0.0/0"), # Trust all proxies (safe for Railway)
# ]
config.force_ssl = false
config.assume_ssl = false

  # --- Logging setup ---
  config.log_tags = [:request_id]
  logger = Logger.new($stdout)
  logger.formatter = Logger::Formatter.new
  config.logger = ActiveSupport::TaggedLogging.new(logger)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym
  config.silence_healthcheck_path = "/up"

  # --- Background jobs ---
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # --- I18n fallbacks ---
  config.i18n.fallbacks = true

  # --- Mailer default host ---
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "example.com"),
    protocol: "https"
  }

  # --- Deprecation reporting ---
  config.active_support.report_deprecations = false
end
