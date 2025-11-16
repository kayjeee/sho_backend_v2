# app/controllers/api/v1/parents_controller.rb
module Api::V1
  class ParentsController < ApplicationController
    before_action :set_parent

    # GET /api/v1/parents/:parent_id/learners
    def learners
      # This assumes the Learner model's parent_info hash contains the parent's auth0_id.
      learners = Learner.where('parent_info.auth0_id' => @parent.auth0_id)
      render json: learners.map(&:to_api_hash), status: :ok
    end

    private

    def set_parent
      @parent = User.find_by(auth0_id: params[:parent_id])
      render json: { error: 'Parent not found' }, status: :not_found unless @parent
    end
  end
end
