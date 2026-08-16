ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Safety check: Prevent running test suite or purging non-test database
unless Rails.env.test?
  raise "FATAL: Test suite must be executed with RAILS_ENV=test (currently '#{Rails.env}')!"
end

current_db = Mongoid.default_client.database.name
if %w[tracker tracker_development development production].include?(current_db.downcase)
  raise "FATAL: Test suite attempted to connect to non-test database '#{current_db}'! Purging forbidden."
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors, with: :threads)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # Note: disabled as this is a pure Mongoid environment with no ActiveRecord
    # fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
