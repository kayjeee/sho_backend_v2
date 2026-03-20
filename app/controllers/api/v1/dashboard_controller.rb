# frozen_string_literal: true

module Api
  module V1
    class DashboardController < ApplicationController
      def overview
        stats = {
          grades_assigned: 0,
          total_learners: 0,
          pending_invitations: 0,
          accepted_invitations: 0,
          performance_trends: [],
          recent_activity: []
        }

        if params[:teacher_id]
          teacher = User.find(params[:teacher_id])
          assignments = TeacherGradeAssignment.by_teacher(teacher.id).active
          stats[:grades_assigned] = assignments.count

          grade_ids = assignments.pluck(:grade_id)
          stats[:total_learners] = Learner.where(:grade_id.in => grade_ids).count
          stats[:pending_invitations] = LearnerInvitation.where(:grade_id.in => grade_ids, status: 'pending').count
          stats[:accepted_invitations] = LearnerInvitation.where(:grade_id.in => grade_ids, status: 'accepted').count
        end

        render_success(data: stats)
      rescue => e
        handle_exception(e, 'Failed to fetch dashboard overview')
      end

      def learner_statistics
        stats = {
          total: Learner.count,
          active: Learner.active.count,
          inactive: Learner.inactive.count,
          graduated: Learner.graduated.count,
          by_gender: {
            male: Learner.where(gender: 0).count,
            female: Learner.where(gender: 1).count,
            other: Learner.where(gender: 2).count
          }
        }
        render_success(data: stats)
      rescue => e
        handle_exception(e, 'Failed to fetch learner statistics')
      end

      def school_statistics
        stats = {
          total_schools: School.count,
          active_schools: School.where(status: 'active').count,
          total_teachers: User.with_role('teacher').count,
          total_parents: User.with_role('parent').count
        }
        render_success(data: stats)
      rescue => e
        handle_exception(e, 'Failed to fetch school statistics')
      end

      def assessment_statistics
        # Assessment model exists but statistics might need more complex queries
        # Providing a basic count for now
        stats = {
          total_assessments: Assessment.count,
          published: Assessment.where(status: 'published').count,
          draft: Assessment.where(status: 'draft').count
        } rescue { message: 'Assessment model not fully compatible with stats yet' }

        render_success(data: stats)
      rescue => e
        handle_exception(e, 'Failed to fetch assessment statistics')
      end

      def performance_trends
        # Placeholder for more complex trend analysis
        render_success(data: { trends: [], message: 'Performance trends analysis not fully implemented' })
      end

      def grade_statistics
        stats = Grade.all.map do |grade|
          {
            id: grade.id.to_s,
            name: grade.name,
            learner_count: grade.learners.count,
            teacher_count: TeacherGradeAssignment.where(grade_id: grade.id).active.count
          }
        end
        render_success(data: { grades: stats })
      rescue => e
        handle_exception(e, 'Failed to fetch grade statistics')
      end
    end
  end
end
