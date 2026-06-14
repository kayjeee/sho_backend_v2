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

          # 1. Resolve Grade context to leverage Mongoid associations and hierarchy logic
          begin
            @grade = Grade.find(grade_id)
          rescue Mongoid::Errors::DocumentNotFound
            return render json: { success: false, error: "Grade not found." }, status: :not_found
          end

          # 2. Use the resilient all_learners method (handles BSON/String mismatches and SchoolClass hierarchy)
          # Fallback to association if method is missing
          @learners = @grade.respond_to?(:all_learners) ? @grade.all_learners : @grade.learners

          # Apply school filter if provided
          if school_id.present?
            @learners = @learners.where(school_id: school_id)
          end

          # 3. Serialization with safety guards for varying schema formats
          render json: {
            success: true,
            total: @learners.count,
            learners: @learners.map { |learner|
              {
                id: learner.id.to_s,
                firstName: learner.try(:firstName) || learner.try(:first_name),
                lastName: learner.try(:lastName) || learner.try(:last_name),
                gender: learner.gender,
                accessionNumber: learner.try(:accessionNumber) || learner.try(:accession_number),
                gradeId: @grade.id.to_s,
                school_id: learner.school_id.to_s,
                parent_id: learner.try(:parent_id)&.to_s || nil
              }
            }
          }, status: :ok
        end
      end
    end
  end
end
