# app/controllers/api/v1/grades_controller.rb
module Api
  module V1
    class GradesController < ApplicationController
      before_action :set_school, only: [ :index, :create ]
      before_action :set_grade, only: [ :show, :update, :destroy, :learners, :teachers, :stats, :invite_learner, :invite_teacher ]

      def index
        service_result = GradeServices::ListGradesService.new(
          school: @school,
          page: params[:page],
          per_page: params[:per_page],
          #  filters: params
        ).call

        if service_result.success
          render json: {
            status: "success",
            data: {
              grades: service_result.grades.map(&:to_api_hash),
              pagination: service_result.pagination
            }
          }
        else
          render json: {
            status: "error",
            message: "Failed to fetch grades",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to fetch grades")
      end

      def show
        render_success(data: { grade: @grade.to_api_hash })
      rescue => e
        handle_exception(e, "Failed to fetch grade")
      end

      def create
        service_result = GradeServices::CreateGradeService.new(
          school: @school,
          grade_params: grade_params
        ).call

        if service_result.success
          render json: {
            status: "success",
            message: "Grade created successfully",
            data: { grade: service_result.grade.to_api_hash }
          }, status: :created
        else
          render json: {
            status: "error",
            message: "Failed to create grade",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to create grade")
      end

      def update
        service_result = GradeServices::UpdateGradeService.new(
          grade: @grade,
          grade_params: grade_params
        ).call

        if service_result.success
          render json: {
            status: "success",
            message: "Grade updated successfully",
            data: { grade: @grade.reload.to_api_hash }
          }
        else
          render json: {
            status: "error",
            message: "Failed to update grade",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to update grade")
      end

      def destroy
        service_result = GradeServices::DeleteGradeService.new(
          grade: @grade
        ).call

        if service_result.success
          render json: {
            status: "success",
            message: "Grade deleted successfully"
          }
        else
          render json: {
            status: "error",
            message: "Failed to delete grade",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to delete grade")
      end

      def learners
        service_result = GradeServices::ListLearnersService.new(
          grade: @grade,
          filters: params
        ).call

        if service_result.success
          render json: {
            status: "success",
            data: {
              learners: service_result.learners.map(&:to_api_hash),
              grade: @grade.to_summary_hash
            }
          }
        else
          render json: {
            status: "error",
            message: "Failed to fetch learners",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to fetch learners")
      end

      def teachers
        service_result = GradeServices::ListTeachersService.new(grade: @grade).call

        if service_result.success
          render json: {
            status: "success",
            data: {
              assignments: service_result.assignments.map(&:to_api_hash),
              grade: @grade.to_summary_hash
            }
          }
        else
          render json: {
            status: "error",
            message: "Failed to fetch teachers",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to fetch teachers")
      end

      def invite_learner
        service_result = GradeServices::InviteLearnerService.new(
          grade: @grade,
          invitation_params: learner_invitation_params
        ).call

        if service_result.success
          render json: {
            status: "success",
            message: "Learner invitation sent successfully",
            data: { invitation: service_result.invitation.to_api_hash }
          }, status: :created
        else
          render json: {
            status: "error",
            message: "Failed to send learner invitation",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to send learner invitation")
      end

      def invite_teacher
        service_result = GradeServices::InviteTeacherService.new(
          grade: @grade,
          invitation_params: teacher_invitation_params
        ).call

        if service_result.success
          render json: {
            status: "success",
            message: "Teacher invitation sent successfully",
            data: { invitation: service_result.invitation.to_api_hash }
          }, status: :created
        else
          render json: {
            status: "error",
            message: "Failed to send teacher invitation",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to send teacher invitation")
      end

      def stats
        service_result = GradeServices::GradeStatsService.new(grade: @grade).call

        if service_result.success
          render json: {
            status: "success",
            data: {
              grade: @grade.to_summary_hash,
              stats: service_result.stats
            }
          }
        else
          render json: {
            status: "error",
            message: "Failed to fetch grade stats",
            errors: service_result.errors
          }, status: :unprocessable_entity
        end
      rescue => e
        handle_exception(e, "Failed to fetch grade stats")
      end

      private

      def set_school
        @school = School.find(params[:school_id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: {
          status: "error",
          message: "School not found"
        }, status: :not_found
      end

      def set_grade
        @grade = Grade.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: {
          status: "error",
          message: "Grade not found"
        }, status: :not_found
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
        render json: {
          status: "success",
          message: message,
          data: data
        }, status: status
      end

      def render_error(message, errors = [], status: :unprocessable_entity)
        render json: {
          status: "error",
          message: message,
          errors: Array(errors)
        }, status: status
      end

      def handle_exception(error, fallback_message)
        Rails.logger.error("❌ #{fallback_message}: #{error.message}")
        render json: {
          status: "error",
          message: fallback_message,
          errors: [ error.message ]
        }, status: :internal_server_error
      end
    end
  end
end
