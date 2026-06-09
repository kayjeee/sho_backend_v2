module Api
  module Admin
    class LearnersController < ApplicationController
      # GET /api/admin/learners?gradeId=...
      def index
        grade_id = params[:gradeId] || params[:grade_id]

        if grade_id.present?
          # Ensure safe fetching based on Mongoid criteria
          # grade_id can be a string or ObjectId depending on how it's stored
          @learners = Learner.where(grade_id: grade_id)

          render json: {
            success: true,
            total: @learners.count,
            learners: @learners.map { |l|
              {
                id: l.id.to_s,
                name: l.try(:full_name) || "#{l.first_name} #{l.last_name}"
              }
            }
          }
        else
          render json: {
            success: false,
            error: "Missing required gradeId parameter"
          }, status: :bad_request
        end
      rescue => e
        handle_unexpected_api_crash(e)
      end
    end
  end
end
