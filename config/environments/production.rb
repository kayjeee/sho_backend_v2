require "active_support/core_ext/integer/time"

Rails.application.configure do
  # --------------------------------------------------
  # Core Rails Settings
  # --------------------------------------------------
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # --------------------------------------------------
  # Logging (Required for Fly.io)
  # --------------------------------------------------
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # --------------------------------------------------
  # Public File Serving (IMPORTANT for Fly)
  # --------------------------------------------------
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}"
  }

  # --------------------------------------------------
  # SSL Settings (Fly terminates SSL at the edge)
  # --------------------------------------------------
  config.assume_ssl = true
  config.force_ssl = false

  # --------------------------------------------------
  # Caching
  # --------------------------------------------------
  config.cache_store = :memory_store

  # --------------------------------------------------
  # Active Job
  # --------------------------------------------------
  config.active_job.queue_adapter = :async

  # --------------------------------------------------
  # Active Storage (if using local storage)
  # --------------------------------------------------
  config.active_storage.service = :local

  # --------------------------------------------------
  # Action Mailer
  # --------------------------------------------------
  config.action_mailer.perform_caching = false

  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost"),
    protocol: "https"
  }

  # --------------------------------------------------
  # I18n
  # --------------------------------------------------
  config.i18n.fallbacks = true

  # --------------------------------------------------
  # Mongoid Compatibility
  # --------------------------------------------------
  # No ActiveRecord settings needed

  # --------------------------------------------------
  # Fly.io Health Check
  # --------------------------------------------------
  config.silence_healthcheck_path = "/up"

  # --------------------------------------------------
  # Host Authorization (IMPORTANT for Fly)
  # --------------------------------------------------
  config.hosts.clear

  # Allow Fly domains
  config.hosts << /.*\.fly\.dev/
  config.hosts << /.*\.fly\.io/

  # Allow custom domain via ENV
  if ENV["APP_HOST"].present?
    config.hosts << ENV["APP_HOST"]
  end

  # --------------------------------------------------
  # Disable Deprecation Logs
  # --------------------------------------------------
  config.active_support.report_deprecations = false
end
