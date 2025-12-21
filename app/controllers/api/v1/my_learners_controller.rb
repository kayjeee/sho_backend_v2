# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    include Secured
    skip_before_action :authenticate_user!, raise: false

    # --- HYBRID AUTHENTICATION FILTERS ---
    before_action :authorize, only: [:index], if: :legacy_my_learners_route?
    before_action :set_user
    before_action :find_learners

    # GET /api/v1/parents/:auth0_id/my_learners (New)
    # GET /api/v1/my_learners (Legacy)
    def index
      return if performed?
      render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
    end

    # GET /api/v1/parents/:auth0_id/profile
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

    # Definitive `find_learners` method with unified query.
    def find_learners
      return unless @user

      # This unified query provides both backward and forward compatibility:
      # - It checks the new `parent_auth0_ids` array for new links.
      # - It checks all legacy fields (`auth0Id`, `userAuth0Id`, `parent_info.auth0_id`) for old data.
      # - It maintains the critical school-scoping for security across all checks.
      @learners = Learner.where(
        '$or' => [
          { :parent_auth0_ids.in => [@user.auth0_id] },
          { auth0Id: @user.auth0_id },
          { userAuth0Id: @user.auth0_id },
          { 'parent_info.auth0_id': @user.auth0_id }
        ],
        :school_id.in => @user.school_ids
      ).active
    end
  end
end
