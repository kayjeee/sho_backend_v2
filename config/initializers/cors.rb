# Define a list of allowed origins. We start with localhost, which is used for local development.
origins = ['http://localhost:3000']

# Add origins from the environment variable, splitting by comma, if it exists.
if ENV['ALLOWED_ORIGINS']
  origins.concat(ENV['ALLOWED_ORIGINS'].split(','))
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Set the allowed origins for CORS, ensuring no duplicates.
    origins origins.uniq

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
