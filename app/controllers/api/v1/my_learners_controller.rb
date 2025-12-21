# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    include Secured
    skip_before_action :authenticate_user!, raise: false

    before_action :authorize, only: [:index], if: :legacy_my_learners_route?
    before_action :set_user
    before_action :find_learners

    def index
      return if performed?
      render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
    end

    def profile
      return if performed?
      render json: { parent: @user.to_api_hash, learner_count: @learners.count }, status: :ok
    end

    private

    def legacy_my_learners_route?
      params[:auth0_id].blank?
    end

    def set_user
      user_auth0_id = legacy_my_learners_route? ? (@decoded_token['sub'] if @decoded_token) : params[:auth0_id]
      return render json: { error: 'Parent identifier not found' }, status: :bad_request unless user_auth0_id

      @user = User.find_by(auth0_id: user_auth0_id)
      render json: { error: 'Parent not found' }, status: :not_found and return unless @user
    end

    # Corrected `find_learners` method as per user instruction.
    def find_learners
      return unless @user

      # This query correctly checks the two fields (`auth0Id`, `userAuth0Id`) that exist
      # in the user's data, ensuring learners are found. It also maintains the critical
      # school-scoping for security.
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
