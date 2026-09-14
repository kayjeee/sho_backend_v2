module Api
  module V1
    class TeacherGradeAssignmentsController < Api::V1::BaseController
      before_action :set_school, only: [:index, :create, :by_school]
      before_action :set_assignment, only: [:show, :update, :destroy, :activate, :deactivate, :terminate, :suspend]

      # GET /api/v1/teacher_grade_assignments
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        scope = TeacherGradeAssignment.by_school(@school.id.to_s)

        grade_id = raw_params[:grade_id] || raw_params["grade_id"] || raw_params[:gradeId] || raw_params["gradeId"]
        teacher_id = raw_params[:teacher_id] || raw_params["teacher_id"] || raw_params[:teacherId] || raw_params["teacherId"]
        status_param = raw_params[:status] || raw_params["status"]

        scope = scope.by_grade(grade_id) if grade_id.present?
        scope = scope.by_teacher(teacher_id) if teacher_id.present?

        if status_param.present?
          if status_param.to_s.match?(/\A\d+\z/)
            scope = scope.where(status: status_param.to_i)
          else
            st_val = TeacherGradeAssignment::STATUSES[status_param.to_s.downcase]
            scope = scope.where(status: st_val) if st_val.present?
          end
        end

        assignments = scope.to_a

        render json: {
          success: true,
          total: assignments.size,
          teacher_grade_assignments: assignments.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("TeacherGradeAssignmentsController#index", e)
      end

      # GET /api/v1/teacher_grade_assignments/:id
      def show
        render json: {
          success: true,
          teacher_grade_assignment: @assignment.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/teacher_grade_assignments
      def create
        raw_payload = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        source = raw_payload[:teacher_grade_assignment] || raw_payload["teacher_grade_assignment"] || raw_payload

        teacher_id = source[:teacher_id] || source["teacher_id"] || source[:teacherId] || source["teacherId"]
        grade_id   = source[:grade_id]   || source["grade_id"]   || source[:gradeId]   || source["gradeId"]
        role_type  = source[:role_type]  || source["role_type"]  || source[:roleType]  || source["roleType"] || 'primary'
        assigned_by_id = source[:assigned_by_id] || source["assigned_by_id"] || source[:assignedById] || source["assignedById"] || params[:user_id]

        if teacher_id.blank?
          return render json: { success: false, error: "teacher_id is required" }, status: :bad_request
        end

        if grade_id.blank?
          return render json: { success: false, error: "grade_id is required" }, status: :bad_request
        end

        # Verify teacher user
        teacher_user = find_user(teacher_id)
        unless teacher_user
          return render json: { success: false, error: "Teacher user not found" }, status: :not_found
        end

        unless teacher_user.roles.map(&:to_s).map(&:downcase).include?('teacher')
          return render json: { success: false, error: "User is not a teacher" }, status: :unprocessable_entity
        end

        # Verify grade belongs to school
        begin
          grade = Grade.find(grade_id)
          if grade.school_id.to_s != @school.id.to_s
            return render json: { success: false, error: "Grade does not belong to target school" }, status: :forbidden
          end
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          return render json: { success: false, error: "Grade not found" }, status: :not_found
        end

        assigned_by_user = find_user(assigned_by_id) || teacher_user

        # Reactivate existing assignment if found for teacher+grade+role_type
        existing = TeacherGradeAssignment.where(
          teacher_id: teacher_user.id,
          grade_id: grade.id,
          role_type: role_type
        ).first

        if existing
          existing.activate! unless existing.active?
          return render json: {
            success: true,
            message: "Teacher grade assignment reactivated successfully",
            teacher_grade_assignment: existing.reload.to_api_hash
          }, status: :ok
        end

        @assignment = TeacherGradeAssignment.new(
          teacher_id: teacher_user.id,
          grade_id: grade.id,
          school_id: @school.id.to_s,
          assigned_by_id: assigned_by_user.id,
          role_type: role_type,
          status: 0,
          assigned_at: Time.current
        )

        if @assignment.save
          render json: {
            success: true,
            message: "Teacher grade assignment created successfully",
            teacher_grade_assignment: @assignment.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            errors: @assignment.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("TeacherGradeAssignmentsController#create", e)
      end

      # PATCH/PUT /api/v1/teacher_grade_assignments/:id
      def update
        source = params[:teacher_grade_assignment].presence || params
        permitted = source.permit(:role_type, :status)

        if @assignment.update(permitted)
          render json: {
            success: true,
            message: "Teacher grade assignment updated successfully",
            teacher_grade_assignment: @assignment.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @assignment.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("TeacherGradeAssignmentsController#update", e)
      end

      # DELETE /api/v1/teacher_grade_assignments/:id
      def destroy
        if @assignment.destroy
          render json: {
            success: true,
            message: "Teacher grade assignment deleted successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @assignment.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/activate
      def activate
        @assignment.activate!
        render json: {
          success: true,
          message: "Teacher grade assignment activated successfully",
          teacher_grade_assignment: @assignment.to_api_hash
        }, status: :ok
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/deactivate
      def deactivate
        @assignment.deactivate!
        render json: {
          success: true,
          message: "Teacher grade assignment deactivated successfully",
          teacher_grade_assignment: @assignment.to_api_hash
        }, status: :ok
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/terminate
      def terminate
        reason = params[:reason]
        @assignment.terminate!(reason)
        render json: {
          success: true,
          message: "Teacher grade assignment terminated successfully",
          teacher_grade_assignment: @assignment.to_api_hash
        }, status: :ok
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/suspend
      def suspend
        reason = params[:reason]
        @assignment.suspend!(reason)
        render json: {
          success: true,
          message: "Teacher grade assignment suspended successfully",
          teacher_grade_assignment: @assignment.to_api_hash
        }, status: :ok
      end

      # GET /api/v1/teacher_grade_assignments/by_teacher/:teacher_id
      def by_teacher
        teacher_id = params[:teacher_id]
        teacher_user = find_user(teacher_id)
        unless teacher_user
          return render json: { success: false, error: "Teacher user not found" }, status: :not_found
        end

        assignments = TeacherGradeAssignment.by_teacher(teacher_user.id).to_a
        render json: {
          success: true,
          total: assignments.size,
          teacher_grade_assignments: assignments.map(&:to_api_hash)
        }, status: :ok
      end

      # GET /api/v1/teacher_grade_assignments/by_grade/:grade_id
      def by_grade
        grade_id = params[:grade_id]
        assignments = TeacherGradeAssignment.by_grade(grade_id).to_a
        render json: {
          success: true,
          total: assignments.size,
          teacher_grade_assignments: assignments.map(&:to_api_hash)
        }, status: :ok
      end

      # GET /api/v1/teacher_grade_assignments/by_school/:school_id
      def by_school
        assignments = TeacherGradeAssignment.by_school(@school.id.to_s).to_a
        render json: {
          success: true,
          total: assignments.size,
          teacher_grade_assignments: assignments.map(&:to_api_hash)
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

        if school_param.blank? && raw_params[:teacher_grade_assignment].is_a?(Hash)
          tga = raw_params[:teacher_grade_assignment]
          school_param = tga[:school_id] || tga["school_id"] || tga[:schoolId] || tga["schoolId"]
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

      def set_assignment
        @assignment = TeacherGradeAssignment.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Teacher grade assignment not found"
        }, status: :not_found and return
      end

      def find_user(user_id)
        return nil if user_id.blank?
        u_str = user_id.to_s
        u_bson = BSON::ObjectId.legal?(u_str) ? BSON::ObjectId.from_string(u_str) : nil

        u_doc = User.collection.find(
          "$or" => [
            { "_id" => { "$in" => [u_str, u_bson].compact } },
            { "auth0_id" => u_str }
          ]
        ).first

        return nil unless u_doc
        User.instantiate(u_doc)
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
