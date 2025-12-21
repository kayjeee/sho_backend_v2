# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    # Remove ALL authentication - no Secured, no authorize
    skip_before_action :authenticate_user!, raise: false

    before_action :set_user
    before_action :find_learners

    def index
      render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
    end

    def profile
      render json: { parent: @user.to_api_hash, learner_count: @learners.count }, status: :ok
    end

    private

    # SIMPLIFIED: Just get user from params[:auth0_id]
    def set_user
      @user = User.find_by(auth0_id: params[:auth0_id])
      render json: { error: 'Parent not found' }, status: :not_found and return unless @user
    end

    def find_learners
      return unless @user

      # Query using correct field names
      @learners = Learner.where(
        '$or' => [
          { auth0Id: @user.auth0_id },
          { userAuth0Id: @user.auth0_id }
        ],
        :school_id.in => @user.school_ids
      ).active
    end
  end
end
