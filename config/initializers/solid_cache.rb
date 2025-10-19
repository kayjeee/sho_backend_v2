# config/initializers/solid_cache.rb
if ENV['SKIP_CACHE_DB'] == 'true'
  module SolidCache
    class Record
      # Prevent ActiveRecord from connecting to the cache DB
      def self.connects_to(**_); end
      def self.establish_connection(*); end
      def self.connection; end
    end
  end
end
