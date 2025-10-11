Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # ✅ Allowed frontend origins
    origins 'https://schoolheadoffice.com', 'http://localhost:3000','schoolheadoffficeinvitations.vercel.app'

    # ✅ Allow all resource paths and headers, with credentials support
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
