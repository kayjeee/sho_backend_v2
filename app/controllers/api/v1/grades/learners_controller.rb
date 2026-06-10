module Api
  module V1
    module Grades
      class LearnersController < ApplicationController
        # GET /api/v1/grades/:grade_id/learners
        def index
          grade_id = params[:grade_id]

          # Fetch users that possess the 'parent' role
          # Scoped to parents in the system
          @learners = User.where(:roles.in => ["parent"])

          # Optional: If parents have a specific grade_id stored in metadata or sub-documents
          # @learners = @learners.where("onboarding_status.client_metadata.grade_id" => grade_id)

          render json: {
            success: true,
            total: @learners.count,
            learners: @learners.map { |user|
              {
                id: user.id.to_s,
                name: user.name || user.email.split('@').first.capitalize,
                email: user.email,
                phone: user.try(:phone) || user.try(:phone_number) || "No Contact",
                status: user.try(:status) || "active",
                roles: user.roles,
                grade_id: grade_id
              }
            }
          }, status: :ok
        end
      end
    end
  end
end
