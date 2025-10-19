# config/initializers/00_solid_cache_patch.rb
if ENV['SKIP_CACHE_DB'] == 'true'
  module SolidCache
    class Record < ActiveRecord::Base
      self.abstract_class = true

      # override connections so Rails won't attempt DB
      def self.connects_to(**_); end
      def self.establish_connection(*); end
      def self.connection; end
    end
  end
end
