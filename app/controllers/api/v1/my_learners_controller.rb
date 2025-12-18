# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    before_action :set_user

    def index
      unless @user
        render json: { error: 'User not found' }, status: :not_found and return
      end

      # New learner-centric logic
      newly_linked_learners = Learner.where(:id.in => @user.learner_ids)

      # Old parent-centric logic for backward compatibility
      learners_in_school = Learner.where(:school_id.in => @user.school_ids)
      legacy_linked_learners = learners_in_school.or(
        {'parent_info.auth0_id' => @user.auth0_id},
        {'auth0Id' => @user.auth0_id},
        {'userAuth0Id' => @user.auth0_id}
      )

      # Combine and unique the learners
      all_learners = (newly_linked_learners.to_a + legacy_linked_learners.to_a).uniq

      response_data = {
        learners: all_learners.map(&:to_api_hash),
        learner_count: all_learners.count
      }

      # For backward compatibility with the old `/profile` route
      if params[:parent_id] && request.path.include?('/profile')
        response_data[:parent] = @user.to_api_hash
      end

      render json: response_data, status: :ok
    end

    private

    def set_user
      if params[:parent_id]
        @user = User.find_by(auth0_id: params[:parent_id])
      else
        @user = current_user
      end
    end

    def current_user
      @current_user ||= if params[:user_email]
        User.find_by(email: params[:user_email])
      elsif request.headers['X-User-Email']
        User.find_by(email: request.headers['X-User-Email'])
      end
    end
  end
end
