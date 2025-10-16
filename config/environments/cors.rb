# config/application.rb or config/initializers/cors.rb
config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'  # Allow all domains, or specify specific domains
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: false  # Set to true if using cookies/auth
  end
end