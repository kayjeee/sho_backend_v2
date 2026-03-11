module GradeServices
  class GradeStatsService
    attr_reader :grade, :errors

    ServiceResult = Struct.new(:success, :errors, :stats, keyword_init: true)

    def initialize(grade:)
      @grade = grade
      @errors = []
    end

    def call
      stats = {
        learner_count: grade.learners.count,
        teacher_count: TeacherGradeAssignment.where(grade_id: grade.id).active.count,
        pending_invitations: LearnerInvitation.where(grade_id: grade.id.to_s, status: 'pending').count,
        accepted_invitations: LearnerInvitation.where(grade_id: grade.id.to_s, status: 'accepted').count
      }

      ServiceResult.new(success: true, stats: stats)
    rescue => e
      Rails.logger.error "❌ Error in GradeStatsService: #{e.message}"
      ServiceResult.new(success: false, errors: [e.message])
    end
  end
end
