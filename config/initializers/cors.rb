Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # ✅ Include both www and non-www domains
    origins 'https://www.schoolheadoffice.com',
            'https://schoolheadoffice.com',
            'https://schoolheadoffficeinvitations.vercel.app',
            'http://localhost:3000'

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
