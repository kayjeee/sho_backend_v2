# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    # This controller is now fully unauthenticated. All JWT-related logic is removed.
    skip_before_action :authenticate_user!, raise: false

    before_action :set_user!
    before_action :find_learners

    # GET /api/v1/parents/:auth0_id/my_learners
    def index
      render json: {
        learners: @learners.map(&:to_api_hash),
        count: @learners.count
      }, status: :ok
    end

    # GET /api/v1/parents/:auth0_id/profile
    def profile
      render json: {
        parent: @user.to_api_hash,
        learner_count: @learners.count
      }, status: :ok
    end

    private

    # Securely finds the user from the URL parameter.
    def set_user!
      @user = User.find_by(auth0_id: params[:auth0_id])
      render json: { error: 'Parent not found' }, status: :not_found and return unless @user
    end

    # Finds learners with an enhanced security check.
    def find_learners
      # This check ensures we don't try to find learners if the user lookup failed.
      return unless @user

      # Enhanced Security: Learners are now filtered by BOTH the explicit parent link
      # AND membership in one of the parent's associated schools. This is a critical
      # defense-in-depth measure to prevent any possible cross-school data leakage.
      @learners = Learner.where(
        :parent_auth0_ids.in => [@user.auth0_id],
        :school_id.in        => @user.school_ids
      ).active
    end
  end
end
