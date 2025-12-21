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

    def find_learners
      return unless @user

      # CRITICAL: Only query by parent_auth0_ids, NOT auth0Id/userAuth0Id
      school_id_strings = @user.school_ids.map(&:to_s)

      @learners = Learner.where(
        :parent_auth0_ids.in => [@user.auth0_id],  # This is the key filter
        :school_id.in => school_id_strings
      ).select { |l| l.status == "active" }

      Rails.logger.info "Parent #{@user.auth0_id} has #{@learners.count} learners"
    end
  end
end
