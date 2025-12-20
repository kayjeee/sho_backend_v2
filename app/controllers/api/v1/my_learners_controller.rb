# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    include Secured
    skip_before_action :authenticate_user!, raise: false

    # --- REFINED AUTHENTICATION FILTERS ---
    before_action :authorize, only: [:index], if: :legacy_my_learners_route?
    before_action :set_user_from_token, only: [:index], if: :legacy_my_learners_route?
    before_action :set_user_from_param, only: [:index, :profile], unless: :legacy_my_learners_route?
    before_action :find_learners

    # GET /api/v1/parents/:auth0_id/my_learners (New)
    # GET /api/v1/my_learners (Legacy)
    def index
      # This guard clause prevents the action from running if a before_action
      # (like `set_user_from_param`) has already rendered an error.
      return if performed?

      if legacy_my_learners_route?
        render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
      else
        render json: { learners: @learners.map(&:to_api_hash), count: @learners.count }, status: :ok
      end
    end

    # GET /api/v1/parents/:auth0_id/profile (Legacy)
    def profile
      # This guard clause is the critical fix for the NoMethodError on nil:NilClass bug.
      return if performed?

      render json: { parent: @user.to_api_hash, learner_count: @learners.count }, status: :ok
    end

    private

    # Checks if the request is for the legacy, token-based route by seeing if :auth0_id is missing.
    def legacy_my_learners_route?
      params[:auth0_id].blank?
    end

    # Finds the user from the JWT token for the legacy route.
    def set_user_from_token
      auth0_id = @decoded_token.token['sub']
      @user = User.find_by(auth0_id: auth0_id)
      render json: { error: 'Authenticated user not found' }, status: :not_found and return unless @user
    end

    # Finds the user from the URL parameter for new/legacy routes.
    def set_user_from_param
      @user = User.find_by(auth0_id: params[:auth0_id])
      render json: { error: 'Parent not found' }, status: :not_found and return unless @user
    end

    # Finds learners for the `@user` after they have been identified.
    def find_learners
      # This check ensures we don't try to find learners if the user lookup failed.
      return unless @user
      @learners = Learner.where(:parent_auth0_ids.in => [@user.auth0_id]).active
    end
  end
end
