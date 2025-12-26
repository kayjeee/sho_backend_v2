# config/initializers/routes_debug.rb

# Only run this initializer in the development environment to avoid
# verbose logging in production and test environments.
if Rails.env.development?
  puts "==> Forcing route reload for debugging..."

  # Ensure all routes are loaded before logging them.
  Rails.application.reload_routes!

  # Log all defined routes to the console on startup.
  # This provides a definitive list of what the application recognizes at boot.
  puts "==> All Application Routes:"
  Rails.application.routes.routes.each do |route|
    # Format the output for readability.
    verb = route.verb.ljust(10)
    path = route.path.spec.to_s
    controller_action = "#{route.defaults[:controller]}##{route.defaults[:action]}"
    puts "  #{verb} #{path.ljust(50)} -> #{controller_action}"
  end

  # Log a summary count to verify the total number of routes loaded.
  puts "✅ Routes successfully loaded: #{Rails.application.routes.routes.size} total routes."
  puts "=================================================="
end
