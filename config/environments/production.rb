require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Disable code reloading between requests
  config.enable_reloading = false

  # Eager load application code for better performance
  config.eager_load = true

  # Disable detailed error reports
  config.consider_all_requests_local = false

  # Enable caching for better performance
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are digest stamped
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.year.to_i}"
  }

  # Enforce SSL (assuming SSL termination handled by proxy)
  config.assume_ssl = true
  config.force_ssl = true

  # Tag logs with request ID for better traceability
  config.log_tags = [:request_id]

  # ✅ Proper logger setup for Rails 8+ and Docker/Render environments
  logger = Logger.new($stdout)
  logger.formatter = Logger::Formatter.new
  config.logger = ActiveSupport::TaggedLogging.new(logger)

  # Default log level (use DEBUG for more verbosity)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Reduce log noise for health checks
  config.silence_healthcheck_path = "/up"

  # Do not show or log deprecations in production
  config.active_support.report_deprecations = false

  # Cache store for Rails (works fine with Redis or memory)
  config.cache_store = :memory_store

  # Optional: disable Active Job if unused
  # If you’re using background jobs with SolidQueue, keep this:
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Enable locale fallbacks (helps with missing translations)
  config.i18n.fallbacks = true

  # ✅ Remove ActiveRecord-specific config — not needed for MongoDB

  # Default URL host for mailers
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "example.com")
  }

  # Optionally configure SMTP if sending emails in production
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.gmail.com",
  #   port: 587,
  #   authentication: :plain,
  #   enable_starttls_auto: true
  # }
end
