module Api
  module Admin
    class GradesController < ApplicationController
      before_action :set_school

      # GET /api/admin/grades?schoolId=far-north-secondary-school
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

      private

      def set_school
        school_id = params[:schoolId] || params[:school_id]

        if BSON::ObjectId.legal?(school_id)
          @school = School.find(school_id)
        else
          # Fallback to lookup by slug/schoolName
          # Converting hyphens back to spaces if it looks like a slug
          lookup_name = school_id.to_s.gsub('-', ' ')
          @school = School.where(schoolName: /^#{Regexp.escape(lookup_name)}$/i).first
        end

        unless @school
          render json: { success: false, message: 'School not found' }, status: :not_found
        end
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: 'School not found' }, status: :not_found
      end
    end
  end
end
