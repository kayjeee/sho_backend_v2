module Api
  module V1
    module Grades
      class LearnersController < Api::V1::BaseController
        def index
          grade_id = params[:grade_id]
          school_id = params[:school_id] || params[:schoolId]

          if grade_id.blank?
            return render json: { success: false, error: "Grade identifier is required." }, status: :bad_request
          end

          # 1. Build dynamic query object matching schema types
          # Handles both raw string storage and BSON ObjectId attributes
          query = {}
          if BSON::ObjectId.legal?(grade_id)
            query[:gradeId] = grade_id.to_s
          else
            query[:gradeId] = grade_id
          end

          if school_id.present?
            query[:school_id] = BSON::ObjectId.legal?(school_id) ? school_id.to_s : school_id
          end

          # 2. Extract genuine Learner documents from the collection
          @learners = Learner.where(query)

          # Fallback query pattern if your schema uses underscores instead of camelCase keys:
          if @learners.count == 0
            alt_query = {}
            alt_query[:grade_id] = BSON::ObjectId.legal?(grade_id) ? BSON::ObjectId.from_string(grade_id) : grade_id
            alt_query[:school_id] = BSON::ObjectId.legal?(school_id) ? BSON::ObjectId.from_string(school_id) : school_id if school_id.present?
            @learners = Learner.where(alt_query)
          end

          # 3. Serialize output fields safely for frontend grid components
          render json: {
            success: true,
            total: @learners.count,
            learners: @learners.map { |learner|
              {
                id: learner.id.to_s,
                firstName: learner.firstName,
                lastName: learner.lastName,
                gender: learner.gender,
                accessionNumber: learner.accessionNumber,
                gradeId: learner.try(:gradeId) || learner.try(:grade_id)&.to_s,
                school_id: learner.school_id.to_s,
                parent_id: learner.try(:parent_id)&.to_s || nil # Reserved placeholder for future linkages
              }
            }
          }, status: :ok
        end
      end
    end
  end
end
