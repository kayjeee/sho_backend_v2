# frozen_string_literal: true

module Api
  module V1
    class TeacherGradeAssignmentsController < ApplicationController
      before_action :set_assignment, only: [:show, :update, :destroy, :activate, :deactivate, :terminate, :suspend]

      # GET /api/v1/teacher_grade_assignments
      def index
        assignments = TeacherGradeAssignment.all
        render_success(data: { assignments: assignments.map(&:to_api_hash) })
      rescue => e
        handle_exception(e, 'Failed to fetch assignments')
      end

      # GET /api/v1/teacher_grade_assignments/:id
      def show
        render_success(data: { assignment: @assignment.to_api_hash })
      rescue => e
        handle_exception(e, 'Failed to fetch assignment')
      end

      # POST /api/v1/teacher_grade_assignments
      def create
        assignment = TeacherGradeAssignment.new(assignment_params)
        assignment.assigned_by_id = params[:assigned_by_id] # Should ideally come from current_user

        if assignment.save
          render_success(
            message: 'Teacher assigned to grade successfully',
            data: { assignment: assignment.to_api_hash },
            status: :created
          )
        else
          render_error('Failed to create assignment', assignment.errors.full_messages)
        end
      rescue => e
        handle_exception(e, 'Failed to create assignment')
      end

      # PATCH/PUT /api/v1/teacher_grade_assignments/:id
      def update
        if @assignment.update(assignment_params)
          render_success(
            message: 'Assignment updated successfully',
            data: { assignment: @assignment.reload.to_api_hash }
          )
        else
          render_error('Failed to update assignment', @assignment.errors.full_messages)
        end
      rescue => e
        handle_exception(e, 'Failed to update assignment')
      end

      # DELETE /api/v1/teacher_grade_assignments/:id
      def destroy
        @assignment.destroy
        render_success(message: 'Assignment removed successfully')
      rescue => e
        handle_exception(e, 'Failed to remove assignment')
      end

      # GET /api/v1/teacher_grade_assignments/by_teacher/:teacher_id
      def by_teacher
        assignments = TeacherGradeAssignment.by_teacher(params[:teacher_id])
        render_success(data: { assignments: assignments.map(&:to_api_hash) })
      end

      # GET /api/v1/teacher_grade_assignments/by_grade/:grade_id
      def by_grade
        assignments = TeacherGradeAssignment.by_grade(params[:grade_id])
        render_success(data: { assignments: assignments.map(&:to_api_hash) })
      end

      # GET /api/v1/teacher_grade_assignments/by_school/:school_id
      def by_school
        assignments = TeacherGradeAssignment.by_school(params[:school_id])
        render_success(data: { assignments: assignments.map(&:to_api_hash) })
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/activate
      def activate
        if @assignment.activate!
          render_success(message: 'Assignment activated', data: { assignment: @assignment.to_api_hash })
        else
          render_error('Failed to activate assignment')
        end
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/deactivate
      def deactivate
        if @assignment.deactivate!
          render_success(message: 'Assignment deactivated', data: { assignment: @assignment.to_api_hash })
        else
          render_error('Failed to deactivate assignment')
        end
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/terminate
      def terminate
        if @assignment.terminate!(params[:reason])
          render_success(message: 'Assignment terminated', data: { assignment: @assignment.to_api_hash })
        else
          render_error('Failed to terminate assignment')
        end
      end

      # PATCH /api/v1/teacher_grade_assignments/:id/suspend
      def suspend
        if @assignment.suspend!(params[:reason])
          render_success(message: 'Assignment suspended', data: { assignment: @assignment.to_api_hash })
        else
          render_error('Failed to suspend assignment')
        end
      end

      private

      def set_assignment
        @assignment = TeacherGradeAssignment.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error('Assignment not found', [], status: :not_found)
      end

      def assignment_params
        params.require(:teacher_grade_assignment).permit(:teacher_id, :grade_id, :school_id, :role_type, :status)
      end
    end
  end
end
