module GradeServices
  class ListTeachersService
    attr_reader :grade, :errors

    ServiceResult = Struct.new(:success, :errors, :assignments, keyword_init: true)

    def initialize(grade:)
      @grade = grade
      @errors = []
    end

    def call
      assignments = TeacherGradeAssignment.where(grade_id: grade.id).active
      ServiceResult.new(success: true, assignments: assignments)
    rescue => e
      Rails.logger.error "❌ Error in ListTeachersService: #{e.message}"
      ServiceResult.new(success: false, errors: [e.message])
    end
  end
end
