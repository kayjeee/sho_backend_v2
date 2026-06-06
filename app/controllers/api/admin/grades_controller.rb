module Api
  module Admin
    class GradesController < ApplicationController
      before_action :set_school
      before_action :set_grade, only: [:show]

      # GET /api/admin/grades?schoolId=far-north-secondary-school
      # GET /api/admin/grades?gradeId=...
      def index
        service_result = GradeServices::ListGradesService.new(
          school: @school,
          page: params[:page],
          per_page: params[:per_page]
        ).call

        if service_result.success
          render json: {
            success: true,
            data: {
              grades: service_result.grades.map(&:to_api_hash),
              pagination: service_result.pagination
            }
          }, status: :ok
        else
          render json: {
            success: false,
            message: 'Failed to fetch grades',
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error("❌ Error fetching grades: #{e.message}")
        render json: {
          success: false,
          message: 'An error occurred',
          errors: [e.message]
        }, status: :internal_server_error
      end

      # GET /api/admin/grades/:id
      # GET /api/admin/grades?gradeId=...
      def show
        render json: {
          success: true,
          grade: @grade.to_api_hash
        }
      end

      private

      def set_school
        school_id = params[:schoolId] || params[:school_id]

        if school_id.present?
          if BSON::ObjectId.legal?(school_id)
            @school = School.find(school_id)
          else
            # Fallback to lookup by slug/schoolName
            lookup_name = school_id.to_s.gsub('-', ' ')
            @school = School.where(schoolName: /^#{Regexp.escape(lookup_name)}$/i).first ||
                      School.where(schoolEmail: /^#{Regexp.escape(school_id.to_s)}$/i).first
          end
        end

        # Fallback resolution from gradeId if schoolId missing
        if @school.nil? && params[:gradeId].present?
          begin
            @grade = Grade.find(params[:gradeId])
            @school = @grade.school if @grade
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            # Handled below
          end
        end

        unless @school || action_name == 'show'
          render json: { success: false, message: 'School not found' }, status: :not_found and return
        end
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: 'School not found' }, status: :not_found and return
      end

      def set_grade
        grade_id = params[:id] || params[:gradeId]
        @grade ||= Grade.find(grade_id)
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, message: 'Grade not found' }, status: :not_found
      end
    end
  end
end
