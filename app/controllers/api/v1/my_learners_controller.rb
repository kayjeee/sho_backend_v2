# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
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

    def set_user
      @user = User.find_by(auth0_id: params[:auth0_id])
      render json: { error: 'Parent not found' }, status: :not_found and return unless @user
    end

    # Corrected `find_learners` to use the definitive array model.
    def find_learners
      return unless @user

      # This query now ONLY looks in the `parent_auth0_ids` array, establishing
      # it as the single source of truth for the parent-learner link.
      @learners = Learner.where(
        :parent_auth0_ids.in => [@user.auth0_id],
        :school_id.in        => @user.school_ids.map(&:to_s) # Ensure IDs are strings for matching
      ).active
    end
  end
end
