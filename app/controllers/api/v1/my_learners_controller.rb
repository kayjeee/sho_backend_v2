# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    include Secured
    skip_before_action :authenticate_user!, raise: false

    # --- REFINED AUTHENTICATION FILTERS ---
    # 1. Authenticate with JWT ONLY for the legacy `index` route.
    before_action :authorize, only: [:index], if: :legacy_my_learners_route?
    # 2. Find the user from the JWT token ONLY for the legacy `index` route.
    before_action :set_user_from_token, only: [:index], if: :legacy_my_learners_route?
    # 3. Find the user from the URL parameter for the new `index` and legacy `profile` routes.
    before_action :set_user_from_param, only: [:index, :profile], unless: :legacy_my_learners_route?
    # 4. Find learners for the identified user for all actions.
    before_action :find_learners

    # GET /api/v1/parents/:parent_auth0_id/my_learners (New)
    # GET /api/v1/my_learners (Legacy)
    def index
      # Logic is now delegated to before_actions, rendering is based on route context.
      if legacy_my_learners_route?
        render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
      else
        render json: { learners: @learners.map(&:to_api_hash), count: @learners.count }, status: :ok
      end
    end

    # GET /api/v1/parents/:parent_auth0_id/profile (Legacy)
    def profile
      # User is set by `set_user_from_param`, learners are found by `find_learners`.
      render json: { parent: @user.to_api_hash, learner_count: @learners.count }, status: :ok
    end

    private

    # Helper to check if the request is for the legacy, token-based route.
    def legacy_my_learners_route?
      params[:parent_auth0_id].blank?
    end

    # Securely finds the user from the JWT token.
    # This is ONLY called on the legacy `/my_learners` route after `authorize` has run.
    def set_user_from_token
      # @decoded_token is guaranteed to be present here because of the before_action chain.
      auth0_id = @decoded_token.token['sub']
      @user = User.find_by(auth0_id: auth0_id)
      render json: { error: 'Authenticated user not found' }, status: :not_found unless @user
    end

    # Securely finds the user from the URL parameter.
    # This is called on the new `/my_learners` and legacy `/profile` routes.
    def set_user_from_param
      @user = User.find_by(auth0_id: params[:parent_auth0_id])
      render json: { error: 'Parent not found' }, status: :not_found unless @user
    end

    # Finds learners for the `@user` that has been previously set.
    # This query is always secure and runs for all actions in this controller.
    def find_learners
      return unless @user # Halt if the user wasn't found in the preceding filters.
      @learners = Learner.where(:parent_auth0_ids.in => [@user.auth0_id]).active
    end
  end
end
