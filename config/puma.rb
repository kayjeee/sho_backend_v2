# Puma configuration for Railway / Production

threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# 🔴 IMPORTANT: Railway requires binding ONLY to ENV["PORT"]
# Do NOT include default fallback like 3000
port ENV.fetch("PORT")

# Bind to all network interfaces (required for Railway containers)
bind "tcp://0.0.0.0:#{ENV.fetch("PORT")}"

# Allow restart via rails command
plugin :tmp_restart

# Solid Queue (Rails 8 background jobs)
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Optional PID file
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Recommended for production stability
environment ENV.fetch("RAILS_ENV", "production")
