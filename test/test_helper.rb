ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "jwt"

# Safety check: Prevent running test suite or purging non-test database
unless Rails.env.test?
  raise "FATAL: Test suite must be executed with RAILS_ENV=test (currently '#{Rails.env}')!"
end

current_db = Mongoid.default_client.database.name
if %w[tracker tracker_development development production].include?(current_db.downcase)
  raise "FATAL: Test suite attempted to connect to non-test database '#{current_db}'! Purging forbidden."
end

# In test environment, stub Auth0Client.validate_token to parse JWT tokens without making external HTTP calls
class Auth0Client
  def self.validate_token(token)
    decoded, _ = JWT.decode(token, nil, false)
    Response.new(Token.new([decoded]), nil)
  rescue => e
    Response.new(nil, Error.new('Bad credentials', :unauthorized))
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors, with: :threads)

    def generate_token_for(user_or_auth0)
      sub = user_or_auth0.is_a?(User) ? user_or_auth0.auth0_id : user_or_auth0.to_s
      JWT.encode({ 'sub' => sub }, 'test_secret', 'HS256')
    end

    def auth_headers_for(user_or_auth0)
      { "Authorization" => "Bearer #{generate_token_for(user_or_auth0)}" }
    end
  end
end
