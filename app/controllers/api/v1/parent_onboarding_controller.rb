# app/controllers/api/v1/parent_onboarding_controller.rb
module Api::V1
  class ParentOnboardingController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    def create
      result = ParentOnboardingService.call(
        invitation_token: params[:invitation_token],
        auth0_id: params[:auth0_id]
      )

      if result[:success]
        render json: { success: true, user: result[:user].to_api_hash, learners: result[:learners].map(&:to_api_hash) }, status: :ok
      else
        render json: { success: false, error: result[:error] }, status: :unprocessable_entity
      end
    end
  end
end
