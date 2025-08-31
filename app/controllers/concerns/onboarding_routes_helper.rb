# app/controllers/concerns/onboarding_routes_helper.rb
module OnboardingRoutesHelper
  extend ActiveSupport::Concern

  # Generate onboarding status URL for a user
  def onboarding_status_url_for(user)
    api_v1_user_onboarding_status_url(user_id: user.auth0_id)
  end

  # Generate complete step URL for a user
  def complete_step_url_for(user)
    complete_step_api_v1_user_onboarding_status_url(user_id: user.auth0_id)
  end

  # Generate skip step URL for a user
  def skip_step_url_for(user)
    skip_step_api_v1_user_onboarding_status_url(user_id: user.auth0_id)
  end

  # Generate complete onboarding URL for a user
  def complete_onboarding_url_for(user)
    complete_api_v1_user_onboarding_status_url(user_id: user.auth0_id)
  end
end