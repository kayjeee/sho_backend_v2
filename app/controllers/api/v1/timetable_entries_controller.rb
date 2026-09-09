module Api
  module V1
    class TimetableEntriesController < Api::V1::BaseController
      before_action :set_school
      before_action :set_timetable_entry, only: [:show, :update, :destroy]

      # GET /api/v1/timetable_entries
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        academic_year = raw_params[:academic_year] || raw_params["academic_year"] || raw_params[:academicYear] || raw_params["academicYear"]
        if academic_year.blank?
          return render json: { success: false, error: "academic_year parameter is required" }, status: :bad_request
        end

        scope = TimetableEntry.by_school(@school.id.to_s).by_academic_year(academic_year)

        class_id = raw_params[:school_class_id] || raw_params["school_class_id"] || raw_params[:schoolClassId] || raw_params["schoolClassId"]
        teacher_id = raw_params[:teacher_id] || raw_params["teacher_id"] || raw_params[:teacherId] || raw_params["teacherId"]

        scope = scope.by_class(class_id) if class_id.present?
        scope = scope.by_teacher(teacher_id) if teacher_id.present?

        entries = scope.to_a

        render json: {
          success: true,
          total: entries.size,
          timetable_entries: entries.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("TimetableEntriesController#index", e)
      end

      # GET /api/v1/timetable_entries/:id
      def show
        render json: {
          success: true,
          timetable_entry: @timetable_entry.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/timetable_entries
      def create
        entry_data = entry_params

        # Validate school ownership of SchoolClass
        if entry_data[:school_class_id].present?
          begin
            school_class = SchoolClass.find(entry_data[:school_class_id])
            if school_class.grade.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "School class does not belong to target school" }, status: :forbidden
            end
            entry_data[:grade_id] = school_class.grade_id.to_s if entry_data[:grade_id].blank?
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "School class not found" }, status: :not_found
          end
        end

        # Validate school ownership of Subject
        if entry_data[:subject_id].present?
          begin
            subject = Subject.find(entry_data[:subject_id])
            if subject.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Subject does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Subject not found" }, status: :not_found
          end
        end

        @timetable_entry = TimetableEntry.new(entry_data)
        @timetable_entry.school_id = @school.id.to_s

        if @timetable_entry.save
          render json: {
            success: true,
            message: "Timetable entry created successfully",
            timetable_entry: @timetable_entry.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            error: @timetable_entry.errors.full_messages.join(", "),
            errors: @timetable_entry.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("TimetableEntriesController#create", e)
      end

      # PATCH/PUT /api/v1/timetable_entries/:id
      def update
        entry_data = entry_params

        if entry_data[:school_class_id].present?
          begin
            school_class = SchoolClass.find(entry_data[:school_class_id])
            if school_class.grade.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "School class does not belong to target school" }, status: :forbidden
            end
            entry_data[:grade_id] = school_class.grade_id.to_s if entry_data[:grade_id].blank?
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "School class not found" }, status: :not_found
          end
        end

        if entry_data[:subject_id].present?
          begin
            subject = Subject.find(entry_data[:subject_id])
            if subject.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Subject does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Subject not found" }, status: :not_found
          end
        end

        if @timetable_entry.update(entry_data)
          render json: {
            success: true,
            message: "Timetable entry updated successfully",
            timetable_entry: @timetable_entry.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            error: @timetable_entry.errors.full_messages.join(", "),
            errors: @timetable_entry.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("TimetableEntriesController#update", e)
      end

      # DELETE /api/v1/timetable_entries/:id
      def destroy
        if @timetable_entry.destroy
          render json: {
            success: true,
            message: "Timetable entry deleted successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @timetable_entry.errors.full_messages
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

        if school_param.blank? && raw_params[:timetable_entry].is_a?(Hash)
          entry_hash = raw_params[:timetable_entry]
          school_param = entry_hash[:school_id] || entry_hash["school_id"] || entry_hash[:schoolId] || entry_hash["schoolId"]
        end

        if school_param.blank? && raw_params["timetable_entry"].is_a?(Hash)
          entry_hash = raw_params["timetable_entry"]
          school_param = entry_hash[:school_id] || entry_hash["school_id"] || entry_hash[:schoolId] || entry_hash["schoolId"]
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

      def set_timetable_entry
        @timetable_entry = TimetableEntry.find(params[:id])
        if @timetable_entry.school_id.to_s != @school.id.to_s
          render json: {
            success: false,
            error: "Timetable entry not found"
          }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Timetable entry not found"
        }, status: :not_found and return
      end

      def entry_params
        source = params[:timetable_entry].presence || params
        source.permit(
          :school_id, :grade_id, :school_class_id, :subject_id, :teacher_id,
          :academic_year, :day_of_week, :start_minute, :end_minute, :room
        )
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
