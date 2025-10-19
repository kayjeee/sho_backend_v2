require "active_support/core_ext/integer/time"

Rails.application.configure do
  # --- Code reloading ---
  config.enable_reloading = true
  config.eager_load = false

  # --- Error reports ---
  config.consider_all_requests_local = true

  # --- Server timing ---
  config.server_timing = true

  # --- Caching ---
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false
  end
  config.cache_store = :memory_store

  # --- Background jobs ---
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # --- Mailers ---
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost"),
    port: ENV.fetch("PORT", 4000)
  }

  # --- Deprecation warnings ---
  config.active_support.deprecation = :log

  # --- Job logs ---
  config.active_job.verbose_enqueue_logs = true

  # --- Runtime annotations (optional for API-only) ---
  config.action_view.annotate_rendered_view_with_filenames = true

  # --- Allowed hosts (ngrok or custom dev domains) ---
  config.hosts << ENV.fetch("DEV_HOST", "localhost")

  # --- I18n fallbacks ---
  config.i18n.fallbacks = true
end
