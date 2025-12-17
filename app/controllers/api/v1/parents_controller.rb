# app/controllers/api/v1/parents_controller.rb
module Api::V1
  class ParentsController < ApplicationController
    before_action :set_parent

    # GET /api/v1/parents/:parent_id/learners
    def learners
      # Scope learners to the parent's schools first
      learners_in_school = Learner.where(:school_id.in => @parent.school_ids)

      # Then, find the specific learners associated with the parent by auth0_id
      learners = learners_in_school.or(
        {'parent_info.auth0_id' => @parent.auth0_id},
        {'auth0Id' => @parent.auth0_id},
        {'userAuth0Id' => @parent.auth0_id}
      )
      render json: learners.map(&:to_api_hash), status: :ok
    end

    def profile
      # Return the parent's profile information
      # Scope learners to the parent's schools first
      learners_in_school = Learner.where(:school_id.in => @parent.school_ids)

      render json: {
        parent: @parent.to_api_hash,
        # Add any additional profile data here
        learner_count: learners_in_school.or(
          {'parent_info.auth0_id' => @parent.auth0_id},
          {'auth0Id' => @parent.auth0_id},
          {'userAuth0Id' => @parent.auth0_id}
        ).count
      }, status: :ok
    end

    private

    def set_parent
      @parent = User.find_by(auth0_id: params[:parent_id])
      render json: { error: 'Parent not found' }, status: :not_found and return unless @parent
    end
  end
end
