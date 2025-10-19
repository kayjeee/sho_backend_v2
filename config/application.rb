require_relative "boot"

# ✅ Instead of require "rails/all", only load what you need
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "sprockets/railtie" # optional if not an API-only app
# ❌ Do NOT require "active_record/railtie"

Bundler.require(*Rails.groups)

module ShoBackendV2
  class Application < Rails::Application
    config.load_defaults 8.0

    # Automatically load code from lib
    config.autoload_lib(ignore: %w[assets tasks])

    # ✅ Tell Rails it’s an API-only app
    config.api_only = true

    # ✅ Skip ActiveRecord completely
    config.generators.orm :mongoid

    # ✅ Optional: prevent connection attempts during builds
    if ENV['SKIP_DB']
      module ActiveRecord
        class Base
          def self.establish_connection(*); end
        end
      end
    end
  end
end
