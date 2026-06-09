module Api
  module V1
    module Grades
      class ClassesController < ApplicationController
        # GET /api/v1/grades/:grade_id/classes
        def index
          grade_id = params[:grade_id]

          if grade_id.blank? || !BSON::ObjectId.legal?(grade_id)
            return render json: {
              success: false,
              error: "Invalid or missing grade token perimeter."
            }, status: :bad_request
          end

          # Find classes matching the parent grade context identifier
          @classes = SchoolClass.where(grade_id: BSON::ObjectId.from_string(grade_id))

          render json: {
            success: true,
            classes: @classes.map { |cls|
              {
                id: cls.id.to_s,
                name: cls.name,
                class_teacher_id: cls.try(:class_teacher_id)&.to_s,
                grade_id: grade_id
              }
            }
          }, status: :ok
        end
      end
    end
  end
end
