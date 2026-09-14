module Api
  module V1
    class SubjectsController < Api::V1::BaseController
      before_action :set_school
      before_action :set_subject, only: [:show, :update, :destroy, :activate, :deactivate]

      # GET /api/v1/subjects
      def index
        subjects = Subject.by_school(@school.id)

        if params[:status].present?
          case params[:status].to_s.downcase
          when 'active', '0'
            subjects = subjects.active
          when 'inactive', '1'
            subjects = subjects.inactive
          end
        end

        render json: {
          success: true,
          total: subjects.count,
          subjects: subjects.map(&:to_api_hash)
        }, status: :ok
      end

      # GET /api/v1/subjects/:id
      def show
        render json: {
          success: true,
          subject: @subject.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/subjects
      def create
        @subject = Subject.new(subject_params)
        @subject.school_id = @school.id.to_s if @subject.school_id.blank?

        if @subject.school_id.to_s != @school.id.to_s
          return render json: {
            success: false,
            error: "Subject school_id does not match target school"
          }, status: :unprocessable_entity
        end

        if @subject.save
          render json: {
            success: true,
            message: "Subject created successfully",
            subject: @subject.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            errors: @subject.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/subjects/:id
      def update
        if subject_params[:school_id].present? && subject_params[:school_id].to_s != @school.id.to_s
          return render json: {
            success: false,
            error: "Cannot change subject school_id to a different school"
          }, status: :unprocessable_entity
        end

        if @subject.update(subject_params)
          render json: {
            success: true,
            message: "Subject updated successfully",
            subject: @subject.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @subject.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/subjects/:id
      def destroy
        if @subject.destroy
          render json: {
            success: true,
            message: "Subject deleted successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @subject.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/subjects/:id/activate
      def activate
        @subject.activate!
        render json: {
          success: true,
          message: "Subject activated successfully",
          subject: @subject.to_api_hash
        }, status: :ok
      end

      # PATCH /api/v1/subjects/:id/deactivate
      def deactivate
        @subject.deactivate!
        render json: {
          success: true,
          message: "Subject deactivated successfully",
          subject: @subject.to_api_hash
        }, status: :ok
      end

      private

      def set_school
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_param = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]

        if school_param.blank? && raw_params[:subject].is_a?(Hash)
          subj = raw_params[:subject]
          school_param = subj[:school_id] || subj["school_id"] || subj[:schoolId] || subj["schoolId"]
        end

        if school_param.blank? && raw_params["subject"].is_a?(Hash)
          subj = raw_params["subject"]
          school_param = subj[:school_id] || subj["school_id"] || subj[:schoolId] || subj["schoolId"]
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

      def set_subject
        @subject = Subject.find(params[:id])
        if @subject.school_id.to_s != @school.id.to_s
          render json: {
            success: false,
            error: "Subject not found"
          }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Subject not found"
        }, status: :not_found and return
      end

      def subject_params
        source = params[:subject].presence || params
        source.permit(:name, :code, :description, :school_id, :status, grade_ids: [])
      end
    end
  end
end
