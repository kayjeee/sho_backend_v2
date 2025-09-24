module GradeServices
  class GradeStatsService
    def initialize(grade:)
      @grade = grade
    end

    def call
      # Example stats calculation — replace with real logic
      stats = {
        learner_count: @grade.learners.count,
        active_count: @grade.learners.where(status: 'active').count
      }

      OpenStruct.new(
        success: true,
        stats: stats,
        errors: []
      )
    rescue => e
      OpenStruct.new(
        success: false,
        stats: {},
        errors: [e.message]
      )
    end
  end
end
