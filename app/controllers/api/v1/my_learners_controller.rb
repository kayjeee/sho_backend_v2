# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    before_action :set_user

    def index
      return render_user_not_found unless @user

      learners = fetch_linked_learners

      response = {
        learners: learners.map(&:to_api_hash),
        learner_count: learners.count
      }

      # Backward compatibility for /profile
      if params[:parent_id] && request.path.include?('/profile')
        response[:parent] = @user.to_api_hash
      end

      render json: response, status: :ok
    end

    private

    def fetch_linked_learners
      # ✅ HARD RULE: no learner_ids = no learners
      return Learner.none unless @user.learner_ids.present?

      Learner.where(:id.in => @user.learner_ids)
    end

    def set_user
      @user =
        if params[:parent_id]
          User.find_by(auth0_id: params[:parent_id])
        else
          current_user
        end
    end

    def current_user
      if params[:user_email]
        User.find_by(email: params[:user_email])
      elsif request.headers['X-User-Email']
        User.find_by(email: request.headers['X-User-Email'])
      end
    end

    def render_user_not_found
      render json: { error: 'User not found' }, status: :not_found
    end
  end
end
