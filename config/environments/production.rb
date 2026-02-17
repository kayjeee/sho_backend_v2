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
  # Railway/Render provide SSL termination, so this can remain true
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" || request.path == "/health" } } }

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

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  # Update this to your actual Railway/Render URL after deployment
  config.action_mailer.default_url_options = { host: ENV.fetch('HOST', 'sho-backend-v2.railway.app') }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  # Since we're using MongoDB, this ActiveRecord setting may not apply
  # config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  # This is ActiveRecord-specific, may not apply to MongoDB
  # config.active_record.attributes_for_inspect = [ :id ]

  # puts "DEBUG: RAILS_ALLOWED_HOSTS from ENV is: #{ENV['RAILS_ALLOWED_HOSTS'].inspect}"

  # Enable DNS rebinding protection and other `Host` header attacks.
  # Allow Railway and Render domains
  config.hosts << ".railway.app"
  config.hosts << /.*\.railway\.app/
  config.hosts << ".onrender.com"
  config.hosts << /.*\.onrender\.com/

  # Add allowed hosts from environment variable.
  # The value should be a comma-separated string of domains, e.g., ".railway.app,example.com"
  if ENV['RAILS_ALLOWED_HOSTS'].present?
    ENV['RAILS_ALLOWED_HOSTS'].split(',').each do |host|
      config.hosts << host.strip
    end
  end

  # Ensure assets are served
  config.public_file_server.enabled = true

  # Skip DNS rebinding protection for the health check endpoints.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" || request.path == "/health" } }
end
