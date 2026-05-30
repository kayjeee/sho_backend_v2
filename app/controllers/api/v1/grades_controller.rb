# app/controllers/api/v1/grades_controller.rb
module Api
  module V1
    class GradesController < ApplicationController
      before_action :set_school, only: [:index, :create]
      before_action :set_grade, only: [:show, :update, :destroy, :learners, :teachers, :stats, :invite_learner, :invite_teacher]

      # GET /api/v1/schools/:school_id/grades
      def index
        # Fetch grades associated with the verified @school
        # We restore the pagination service for production resilience as per review feedback
        service_result = GradeServices::ListGradesService.new(
          school: @school,
          page: params[:page],
          per_page: params[:per_page],
        ).call

        if service_result.success
          render_success(
            message: "Grades retrieved successfully",
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
        Rails.logger.info "🔍🔍🔍 STARTING LEARNERS ENDPOINT 🔍🔍🔍"
        Rails.logger.info "🔍 Grade ID from params: #{params[:id]}"
        Rails.logger.info "🔍 Grade instance ID: #{@grade.id}"

        # Use the correct scope defined in your model
        learners = @grade.learners 
        Rails.logger.info "🔍 Raw learners query count: #{learners.count}"

        # Filter by school_id if provided
        if params[:school_id].present?
          learners = learners.by_school(params[:school_id])
          Rails.logger.info "🔍 After school filter count: #{learners.count}"
        end

        # Filter by status if provided
        if params[:status].present?
          status_value = case params[:status].downcase
                         when 'active' then 0
                         when 'inactive' then 1
                         when 'graduated' then 2
                         else params[:status].to_i
                         end
          learners = learners.where(status: status_value)
          Rails.logger.info "🔍 After status filter count: #{learners.count}"
        end

        # Basic pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 20).to_i
        total_count = learners.count
        learners_paginated = learners.skip((page - 1) * per_page).limit(per_page)
        
        Rails.logger.info "🔍 Paginated learners count: #{learners_paginated.count}"

        # Debug: log actual learner data
        if learners_paginated.any?
          Rails.logger.info "🔍 FIRST LEARNER IN RESULTS:"
          first = learners_paginated.first
          Rails.logger.info "🔍    ID: #{first.id}"
          Rails.logger.info "🔍    Name: #{first.first_name} #{first.last_name}"
          Rails.logger.info "🔍    Grade ID: #{first.grade_id}"
          Rails.logger.info "🔍    Status: #{first.status} (#{first.status_text})"
        else
          Rails.logger.info "🔍 NO LEARNERS FOUND"
        end

        # Use the to_api_hash method to correctly serialize the data.
        # This will return full_name, first_name, and last_name as snake_case.
        learners_data = learners_paginated.map(&:to_api_hash)

        Rails.logger.info "🔍 Serialized learners data count: #{learners_data.count}"
        
        response = {
          status: 'success',
          data: {
            learners: learners_data,
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

        Rails.logger.info "🔍🔍🔍 ENDING LEARNERS ENDPOINT - SUCCESS 🔍🔍🔍"
        render json: response

      rescue => e
        Rails.logger.error "❌❌❌ ERROR IN LEARNERS ENDPOINT: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          status: 'error',
          message: 'Failed to fetch learners',
          errors: [e.message]
        }, status: :internal_server_error
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
        if BSON::ObjectId.legal?(params[:school_id])
          @school = School.find(params[:school_id])
        else
          # If frontend passes the slug string 'far-north-secondary-school' directly:
          # Look it up via text regex or a dedicated slug field if available
          formatted_query = params[:school_id].to_s.gsub('-', ' ')
          @school = School.where(schoolName: /^#{Regexp.escape(formatted_query)}$/i).first ||
                    School.find_by(slug: params[:school_id])
        end

        raise Mongoid::Errors::DocumentNotFound.new(School, { _id: params[:school_id] }) unless @school
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { error: "School location context not found" }, status: :not_found
      end

      def set_grade
        grade_id = params[:id] || params[:grade_id]

        if grade_id.blank?
          Rails.logger.warn "⚠️ set_grade: grade_id is nil or blank. params: #{params.inspect}"
          return render_error('Grade ID is required', [], status: :bad_request)
        end

        @grade = Grade.find(grade_id)
      rescue Mongoid::Errors::DocumentNotFound
        render_error('Grade not found', [], status: :not_found)
      rescue BSON::Error::InvalidObjectId
        render_error('Invalid Grade ID format', [], status: :bad_request)
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
        params.require(:invitation).permit(
          :recipient_phone_number,
          :phone_number,
          :parent_name,
          :learner_number,
          :invited_via,
          :country_code,
          :country_name,
          :expires_at,
          learner_numbers: [],
          learner_ids: []
        )
      end

      def teacher_invitation_params
        params.require(:invitation).permit(:recipient_phone_number, :teacher_name, :invited_via, :expires_at, assigned_grades: [], invitation_data: {})
      end
    end
  end
end
