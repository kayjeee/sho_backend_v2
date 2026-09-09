Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Include both www and non-www domains, vercel app, localhost, and 127.0.0.1 on any port in development
    origins 'https://www.schoolheadoffice.com',
            'https://schoolheadoffice.com',
            'https://schoolheadoffficeinvitations.vercel.app',
            'http://localhost:3000',
            /\Ahttp:\/\/localhost(:\d+)?\z/,
            /\Ahttp:\/\/127\.0\.0\.1(:\d+)?\z/

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
