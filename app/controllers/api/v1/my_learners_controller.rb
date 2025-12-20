# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    include Secured

    # --- HYBRID AUTHENTICATION ---
    # This controller now supports two modes for backward compatibility:
    # 1. New, Unauthenticated (URL-based): Skips auth if a `parent_auth0_id` is present.
    # 2. Legacy, Authenticated (JWT-based): Requires a token if the old `/my_learners` route is used.
    skip_before_action :authenticate_user!, raise: false
    before_action :authorize, only: [:index], if: :legacy_my_learners_route?

    before_action :set_user_and_learners!

    # GET /api/v1/parents/:parent_auth0_id/my_learners (New)
    # GET /api/v1/my_learners (Legacy)
    #
    # Securely fetches learners for a user, identified either by a URL
    # parameter or a JWT token.
    def index
      # Renders learners. The JSON shape is adjusted for backward compatibility.
      if legacy_my_learners_route?
        render json: {
          learners: @learners.map(&:to_api_hash),
          learner_count: @learners.count # Legacy key is "learner_count"
        }, status: :ok
      else
        render json: {
          learners: @learners.map(&:to_api_hash),
          count: @learners.count # New key is "count"
        }, status: :ok
      end
    end

    # GET /api/v1/parents/:parent_auth0_id/profile (Legacy)
    #
    # Renders the parent's profile and learner count in the exact legacy format
    # to ensure the frontend continues to work.
    def profile
      render json: {
        parent: @user.to_api_hash, # The exact legacy JSON shape
        learner_count: @learners.count
      }, status: :ok
    end

    private

    # Determines if the request is for the old, token-based route.
    def legacy_my_learners_route?
      params[:parent_auth0_id].blank?
    end

    # A single, unified method to find the user and their learners,
    # handling both authentication methods.
    def set_user_and_learners!
      user_auth0_id = if legacy_my_learners_route?
        # Legacy Mode: Get user ID from the JWT token provided by `authorize`.
        @decoded_token.token['sub']
      else
        # New Mode: Get user ID from the URL parameter.
        params[:parent_auth0_id]
      end

      @user = User.find_by(auth0_id: user_auth0_id)
      return render json: { error: 'Parent not found' }, status: :not_found unless @user

      # The learner query is ALWAYS secure, regardless of how the user was identified.
      @learners = Learner.where(:parent_auth0_ids.in => [@user.auth0_id]).active
    end
  end
end
