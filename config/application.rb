require_relative "boot"

require "rails"

# Load ONLY the frameworks we actually use
require "active_model/railtie"
require "active_job/railtie"

require "action_controller/railtie"
require "action_mailer/railtie"

# ❌ Do NOT load ActionText (requires ActiveRecord)
# ❌ Do NOT load ActionMailbox
# ❌ Do NOT load ActiveRecord

require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Load gems
Bundler.require(*Rails.groups)

module ShoBackendV2
  class Application < Rails::Application
    # Initialize defaults
    config.load_defaults 8.0

    # Autoload lib folder
    config.autoload_lib(ignore: %w[assets tasks])

    # Explicitly disable ActiveRecord
    config.generators do |g|
      g.orm :mongoid
      g.test_framework nil
    end
  end
end
