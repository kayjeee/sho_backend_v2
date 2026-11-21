require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true
  
  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Use memory store for caching (compatible with MongoDB)
  config.cache_store = :memory_store

  # Use async adapter for Active Job or comment out if not using background jobs
  config.active_job.queue_adapter = :async

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch('RAILWAY_PUBLIC_DOMAIN', 'shobackendv2-production.up.railway.app') }

  # Enable locale fallbacks for I18n
  config.i18n.fallbacks = true

  # Allow Railway domain, Railway wildcard subdomains, and localhost
  config.hosts << "shobackendv2-production.up.railway.app"
  config.hosts << /.*\.up\.railway\.app/
  config.hosts << /.*\.onrender\.com/ # Kept in case you cross-deploy

  if ENV["ALLOWED_HOSTS"].present?
    config.hosts.concat(ENV["ALLOWED_HOSTS"].split(","))
  end

  # Enable ActionCable allowed request origins for Railway WebSockets
  config.action_cable.allowed_request_origins = [
    /https?:\/\/.*\.up\.railway\.app/,
    /https?:\/\/localhost:.*/
  ]

  # Ensure assets are served
  config.public_file_server.enabled = true
end