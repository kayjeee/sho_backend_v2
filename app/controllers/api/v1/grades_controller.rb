# app/controllers/api/v1/grades_controller.rb
module Api
  module V1
    class GradesController < ApplicationController
      before_action :set_school, only: [:index, :create]
      before_action :set_grade, only: [:show, :update, :destroy, :learners, :teachers, :stats, :invite_learner, :invite_teacher]

      # GET /schools/:school_id/grades
      def index
        service_result = GradeServices::ListGradesService.new(
          school: @school,
          page: params[:page],
          per_page: params[:per_page],
        ).call

        if service_result.success
          render_success(
            data: {
              grades: service_result.grades.map(&:to_api_hash),
              pagination: service_result.pagination
            }
          )
        else
          render_error('Failed to fetch grades', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to fetch grades')
      end

      # GET /grades/:id
      def show
        render_success(data: { grade: @grade.to_api_hash })
      rescue => e
        handle_exception(e, 'Failed to fetch grade')
      end

      # POST /schools/:school_id/grades
      def create
        service_result = GradeServices::CreateGradeService.new(
          school: @school,
          grade_params: grade_params
        ).call

        if service_result.success
          render_success(
            message: 'Grade created successfully',
            data: { grade: service_result.grade.to_api_hash },
            status: :created
          )
        else
          render_error('Failed to create grade', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to create grade')
      end

      # PUT /grades/:id
      def update
        service_result = GradeServices::UpdateGradeService.new(
          grade: @grade,
          grade_params: grade_params
        ).call

        if service_result.success
          render_success(
            message: 'Grade updated successfully',
            data: { grade: @grade.reload.to_api_hash }
          )
        else
          render_error('Failed to update grade', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to update grade')
      end

      # DELETE /grades/:id
      def destroy
        service_result = GradeServices::DeleteGradeService.new(
          grade: @grade
        ).call

        if service_result.success
          render_success(message: 'Grade deleted successfully')
        else
          render_error('Failed to delete grade', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to delete grade')
      end

      # GET /grades/:id/learners
     def learners
  # Base query: all learners for this grade
  learners = Learner.where(gradeId: @grade.id.to_s)

  # Filter by school_id if provided
  learners = learners.where(school_id: params[:school_id]) if params[:school_id].present?

  # Filter by status (case-insensitive exact match)
  learners = learners.where(status: params[:status].downcase) if params[:status].present?

  # Pagination
  page = (params[:page] || 1).to_i
  per_page = [(params[:per_page] || 20).to_i, 100].min
  total_count = learners.count
  learners = learners.skip((page - 1) * per_page).limit(per_page)

  render json: {
    status: 'success',
    data: {
      learners: learners.map do |learner|
        {
          id: learner.id.to_s,
          firstName: learner.firstName,
          lastName: learner.lastName,
          gender: learner.gender,
          accessionNumber: learner.accessionNumber,
          gradeId: learner.gradeId,
          school_id: learner.school_id,
          status: learner.status,
          created_at: learner.created_at,
          updated_at: learner.updated_at
        }
      end,
      grade: {
        id: @grade.id.to_s,
        name: @grade.name,
        grade_level: @grade.grade_level,
        description: @grade.description
      }
    },
    pagination: {
      current_page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: (total_count.to_f / per_page).ceil
    }
  }
rescue => e
  handle_exception(e, 'Failed to fetch learners')
end




      # GET /grades/:id/teachers
      def teachers
        service_result = GradeServices::ListTeachersService.new(grade: @grade).call

        if service_result.success
          render_success(
            data: {
              assignments: service_result.assignments.map(&:to_api_hash),
              grade: @grade.to_summary_hash
            }
          )
        else
          render_error('Failed to fetch teachers', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to fetch teachers')
      end

      # POST /grades/:id/invite_learner
      def invite_learner
        service_result = GradeServices::InviteLearnerService.new(
          grade: @grade,
          invitation_params: learner_invitation_params
        ).call

        if service_result.success
          render_success(
            message: 'Learner invitation sent successfully',
            data: { invitation: service_result.invitation.to_api_hash },
            status: :created
          )
        else
          render_error('Failed to send learner invitation', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to send learner invitation')
      end

      # POST /grades/:id/invite_teacher
      def invite_teacher
        service_result = GradeServices::InviteTeacherService.new(
          grade: @grade,
          invitation_params: teacher_invitation_params
        ).call

        if service_result.success
          render_success(
            message: 'Teacher invitation sent successfully',
            data: { invitation: service_result.invitation.to_api_hash },
            status: :created
          )
        else
          render_error('Failed to send teacher invitation', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to send teacher invitation')
      end

      # GET /grades/:id/stats
      def stats
        service_result = GradeServices::GradeStatsService.new(grade: @grade).call

        if service_result.success
          render_success(
            data: {
              grade: @grade.to_summary_hash,
              stats: service_result.stats
            }
          )
        else
          render_error('Failed to fetch grade stats', service_result.errors)
        end
      rescue => e
        handle_exception(e, 'Failed to fetch grade stats')
      end

      private

      def set_school
        @school = School.find(params[:school_id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error('School not found', [], :not_found)
      end

      def set_grade
        @grade = Grade.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error('Grade not found', [], :not_found)
      end

      def grade_params
        params.require(:grade).permit(
          :name, :description, :grade_level, :capacity,
          :min_age, :max_age, :status, :fees,
          :academic_year_start, :academic_year_end,
          curriculum_info: {}, schedule_info: {}
        )
      end

      def learner_invitation_params
        params.require(:invitation).permit(:learner_email, :learner_phone, :expires_at, invitation_data: {})
      end

      def teacher_invitation_params
        params.require(:invitation).permit(:teacher_email, :expires_at, assigned_grades: [], invitation_data: {})
      end

      def render_success(message: nil, data: {}, status: :ok)
        render json: { status: 'success', message: message, data: data }, status: status
      end

      def render_error(message, errors = [], status: :unprocessable_entity)
        render json: { status: 'error', message: message, errors: Array(errors) }, status: status
      end

      def handle_exception(error, fallback_message)
        Rails.logger.error("❌ #{fallback_message}: #{error.message}")
        render json: { status: 'error', message: fallback_message, errors: [error.message] }, status: :internal_server_error
      end
    end
  end
end
