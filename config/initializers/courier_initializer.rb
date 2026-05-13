# frozen_string_literal: true

# config/initializers/courier.rb
#
# The trycourier gem reads COURIER_API_KEY from ENV automatically.
# This initializer validates the key is present at boot time so the app
# fails loudly in development/CI rather than silently at notification time.
#
# In production, set COURIER_API_KEY and COURIER_TEMPLATE_ID via your
# secrets manager (e.g. Rails credentials, Doppler, Heroku config vars).

unless ENV["COURIER_API_KEY"].present?
  message = "[Courier] COURIER_API_KEY is not set. " \
            "Notifications will not be delivered."

  if Rails.env.production?
    raise "COURIER_API_KEY must be set in production"
  else
    Rails.logger.warn message
  end
end

unless ENV["COURIER_TEMPLATE_ID"].present?
  Rails.logger.warn(
    "[Courier] COURIER_TEMPLATE_ID is not set. " \
    "NotificationService will raise KeyError at runtime."
  )
end