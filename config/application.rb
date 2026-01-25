# frozen_string_literal: true

require_relative "boot"

require "rails"

# --------------------------------------------
# Load ONLY the frameworks we actually use
# --------------------------------------------
require "active_model/railtie"
require "active_job/railtie"

require "action_controller/railtie"
require "action_mailer/railtie"

# ❌ DO NOT load ActiveRecord (Mongoid only)
# ❌ DO NOT load ActionText
# ❌ DO NOT load ActionMailbox

require "action_view/railtie"
require "action_cable/engine"

# Optional – remove if not using Rails test unit
require "rails/test_unit/railtie"

# --------------------------------------------
# Load gems listed in the Gemfile
# --------------------------------------------
Bundler.require(*Rails.groups)

module ShoBackendV2
  class Application < Rails::Application
    # --------------------------------------------
    # Initialize configuration defaults
    # --------------------------------------------
    config.load_defaults 8.0

    # --------------------------------------------
    # Zeitwerk / Autoloading
    # --------------------------------------------
    # app/lib is for domain objects like Result, Value Objects, etc.
    config.autoload_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/lib")

    # Ignore non-code lib folders
    config.autoload_lib(ignore: %w[assets tasks generators])

    # --------------------------------------------
    # API-only mindset (but keep ActionView loaded)
    # --------------------------------------------
    config.api_only = false

    # --------------------------------------------
    # Generators
    # --------------------------------------------
    config.generators do |g|
      g.orm :mongoid
      g.test_framework nil
      g.assets false
      g.helper false
    end

    # --------------------------------------------
    # ActiveJob (optional)
    # --------------------------------------------
    config.active_job.queue_adapter = :async

    # --------------------------------------------
    # Timezone / I18n
    # --------------------------------------------
    config.time_zone = "Africa/Johannesburg"
    config.i18n.default_locale = :en

    # --------------------------------------------
    # Security / Params
    # --------------------------------------------
    config.action_controller.permit_all_parameters = false
  end
end
