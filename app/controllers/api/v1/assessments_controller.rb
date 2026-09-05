module Api
  module V1
    class AssessmentsController < Api::V1::BaseController
      before_action :set_school
      before_action :set_assessment, only: [:show, :update, :destroy]

      # GET /api/v1/assessments
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        scope = Assessment.by_school(@school.id.to_s)

        grade_id = raw_params[:grade_id] || raw_params["grade_id"] || raw_params[:gradeId] || raw_params["gradeId"]
        subject_id = raw_params[:subject_id] || raw_params["subject_id"] || raw_params[:subjectId] || raw_params["subjectId"]
        academic_year = raw_params[:academic_year] || raw_params["academic_year"] || raw_params[:academicYear] || raw_params["academicYear"]
        term = raw_params[:term] || raw_params["term"]

        scope = scope.by_grade(grade_id) if grade_id.present?
        scope = scope.by_subject(subject_id) if subject_id.present?
        scope = scope.by_academic_year(academic_year) if academic_year.present?
        scope = scope.by_term(term) if term.present?

        assessments = scope.to_a

        render json: {
          success: true,
          total: assessments.size,
          assessments: assessments.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("AssessmentsController#index", e)
      end

      # GET /api/v1/assessments/:id
      def show
        render json: {
          success: true,
          assessment: @assessment.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/assessments
      def create
        ass_data = assessment_params

        # Validate Grade belongs to school
        if ass_data[:grade_id].present?
          begin
            grade = Grade.find(ass_data[:grade_id])
            if grade.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Grade does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Grade not found" }, status: :not_found
          end
        end

        # Validate Subject belongs to school
        if ass_data[:subject_id].present?
          begin
            subject = Subject.find(ass_data[:subject_id])
            if subject.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Subject does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Subject not found" }, status: :not_found
          end
        end

        @assessment = Assessment.new(ass_data)
        @assessment.school_id = @school.id.to_s

        if @assessment.save
          render json: {
            success: true,
            message: "Assessment created successfully",
            assessment: @assessment.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            errors: @assessment.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("AssessmentsController#create", e)
      end

      # PATCH/PUT /api/v1/assessments/:id
      def update
        ass_data = assessment_params

        if ass_data[:grade_id].present?
          begin
            grade = Grade.find(ass_data[:grade_id])
            if grade.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Grade does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Grade not found" }, status: :not_found
          end
        end

        if ass_data[:subject_id].present?
          begin
            subject = Subject.find(ass_data[:subject_id])
            if subject.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Subject does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Subject not found" }, status: :not_found
          end
        end

        if @assessment.update(ass_data)
          render json: {
            success: true,
            message: "Assessment updated successfully",
            assessment: @assessment.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @assessment.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("AssessmentsController#update", e)
      end

      # DELETE /api/v1/assessments/:id
      def destroy
        if @assessment.destroy
          render json: {
            success: true,
            message: "Assessment deleted successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @assessment.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def set_school
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_param = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]

        if school_param.blank? && raw_params[:assessment].is_a?(Hash)
          ass_hash = raw_params[:assessment]
          school_param = ass_hash[:school_id] || ass_hash["school_id"] || ass_hash[:schoolId] || ass_hash["schoolId"]
        end

        if school_param.blank? && raw_params["assessment"].is_a?(Hash)
          ass_hash = raw_params["assessment"]
          school_param = ass_hash[:school_id] || ass_hash["school_id"] || ass_hash[:schoolId] || ass_hash["schoolId"]
        end

        if school_param.blank?
          render json: {
            success: false,
            error: "School context identifier is required."
          }, status: :bad_request and return
        end

        @school = find_school_by_id_or_slug(school_param)
        unless @school
          render json: {
            success: false,
            error: "School not found"
          }, status: :not_found and return
        end
      rescue AmbiguousSchoolError => e
        render json: {
          success: false,
          error: e.message,
          matching_schools: e.matching_schools.map { |s| { id: s.id.to_s, name: s.schoolName } }
        }, status: :conflict and return
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "School not found"
        }, status: :not_found and return
      end

      def set_assessment
        @assessment = Assessment.find(params[:id])
        if @assessment.school_id.to_s != @school.id.to_s
          render json: {
            success: false,
            error: "Assessment not found"
          }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Assessment not found"
        }, status: :not_found and return
      end

      def assessment_params
        source = params[:assessment].presence || params
        source.permit(:school_id, :grade_id, :subject_id, :academic_year, :term, :name, :max_score, :date)
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
