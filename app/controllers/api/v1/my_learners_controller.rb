# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    # This controller is now unauthenticated and relies on the explicit parent_auth0_id from the URL.
    # We remove all token-based authentication.
    skip_before_action :authenticate_user!, raise: false

    before_action :set_user!

    # GET /api/v1/parents/:parent_auth0_id/my_learners
    #
    # Securely fetches learners for a given parent based on the explicit
    # `parent_auth0_ids` link, without requiring JWT authentication.
    def index
      # The user's identity is established by `set_user!` using the URL parameter.
      # The query is secure because it ONLY finds learners who have the parent's
      # specific `auth0_id` in their `parent_auth0_ids` array. This prevents
      # any possibility of leaking learners from other parents or schools.
      learners = Learner.where(:parent_auth0_ids.in => [@user.auth0_id]).active

      render json: {
        learners: learners.map(&:to_api_hash),
        count: learners.count
      }, status: :ok
    end

    private

    def set_user!
      # Find the user (parent) directly from the `parent_auth0_id` URL parameter.
      @user = User.find_by(auth0_id: params[:parent_auth0_id])

      # If no user is found with that ID, return a 404 error.
      render json: { error: 'Parent not found' }, status: :not_found unless @user
    end
  end
end
