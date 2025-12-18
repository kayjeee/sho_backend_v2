# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    before_action :authenticate_user! # Assuming you have a way to authenticate the current_user

    def index
      # New learner-centric logic
      newly_linked_learners = Learner.where(:id.in => current_user.learner_ids)

      # Old parent-centric logic for backward compatibility
      learners_in_school = Learner.where(:school_id.in => current_user.school_ids)
      legacy_linked_learners = learners_in_school.or(
        {'parent_info.auth0_id' => current_user.auth0_id},
        {'auth0Id' => current_user.auth0_id},
        {'userAuth0Id' => current_user.auth0_id}
      )

      # Combine and unique the learners
      all_learners = (newly_linked_learners.to_a + legacy_linked_learners.to_a).uniq

      render json: {
        learners: all_learners.map(&:to_api_hash),
        learner_count: all_learners.count
      }, status: :ok
    end
  end
end
