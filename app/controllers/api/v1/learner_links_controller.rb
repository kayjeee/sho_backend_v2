# app/controllers/api/v1/learner_links_controller.rb
module Api::V1
  class LearnerLinksController < ApplicationController
    skip_before_action :authenticate_user!, raise: false
    before_action :set_user

    def create
      return render_user_not_found unless @user

      learner = find_learner_by_number
      return render_learner_not_found unless learner

      # 🔒 Prevent duplicate linking
      if @user.learner_ids&.include?(learner.id)
        return render json: {
          message: 'Learner already linked'
        }, status: :ok
      end

      # 🔐 OPTIONAL: restrict linking to user schools (if needed)
      if @user.school_ids.present? &&
         !@user.school_ids.map(&:to_s).include?(learner.school_id.to_s)
        return render json: {
          error: 'Learner does not belong to your school'
        }, status: :forbidden
      end

      # ✅ LINK
      @user.push(learner_ids: learner.id.to_s)

      render json: {
        message: 'Learner linked successfully',
        learner: learner.to_api_hash
      }, status: :created
    end

    private

    def find_learner_by_number
      Learner.find_by(
        accession_number: params[:learner_number]
      )
    end

    def set_user
      @user =
        if params[:user_email]
          User.find_by(email: params[:user_email])
        elsif request.headers['X-User-Email']
          User.find_by(email: request.headers['X-User-Email'])
        elsif params[:auth0_id]
          User.find_by(auth0_id: params[:auth0_id])
        end
    end

    def render_user_not_found
      render json: { error: 'User not found' }, status: :not_found
    end

    def render_learner_not_found
      render json: { error: 'Invalid learner number' }, status: :not_found
    end
  end
end
