module GradeServices
  class CreateGradeService
    attr_reader :school, :grade_params, :errors

    ServiceResult = Struct.new(:success, :errors, :grade, keyword_init: true)

    def initialize(school:, grade_params:)
      @school = school
      @grade_params = grade_params
      @errors = []
    end

    def call
      # No permission validation since no user context
      create_grade
    end

    private

    def create_grade
      grade = school.grades.build(grade_params)

      if grade.save
        # No audit log for created_by since removed
        ServiceResult.new(success: true, grade: grade)
      else
        Rails.logger.error "❌ Failed to create grade: #{grade.errors.full_messages.join(', ')}"
        ServiceResult.new(success: false, errors: grade.errors.full_messages)
      end
    end
  end
end
