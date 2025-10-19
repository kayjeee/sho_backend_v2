require_relative "boot"

# ✅ Load only what you actually use — no ActiveRecord or Sprockets
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
# ❌ Do NOT require "active_record/railtie"
# ❌ Do NOT require "sprockets/railtie"

Bundler.require(*Rails.groups)

module ShoBackendV2
  class Application < Rails::Application
    config.load_defaults 8.0

    # ✅ API-only app
    config.api_only = true

    # ✅ No ActiveRecord; use Mongoid
    config.generators.orm :mongoid

    # Optional: skip DB connection for build environments
    if ENV['SKIP_DB']
      module ActiveRecord
        class Base
          def self.establish_connection(*); end
        end
      end
    end

    # ✅ Automatically load code from lib/
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
