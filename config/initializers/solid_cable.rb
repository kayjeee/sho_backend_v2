# config/initializers/solid_cable.rb
if ENV['SKIP_DB']
  module SolidCable
    class Record
      # Prevent ActiveRecord connection
      def self.connection; end
      def self.establish_connection(*); end
    end
  end
end
