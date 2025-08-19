module GradeServices
  class DeleteGradeService
    attr_reader :grade, :user, :errors

    ServiceResult = Struct.new(:success, :errors, keyword_init: true)

    def initialize(grade:, user: nil)
      @grade = grade
      @user = user
      @errors = []
    end

    def call
      validate_permissions unless user.nil?
      return ServiceResult.new(success: false, errors: errors) if errors.any?

      validate_deletion_constraints
      return ServiceResult.new(success: false, errors: errors) if errors.any?

      delete_grade
    end

    private

    def validate_permissions
      unless can_delete_grade?
        errors << "You don't have permission to delete this grade"
      end
    end

    def can_delete_grade?
      return true if user.roles.include?("Admin")
      return true if grade.respond_to?(:created_by) && grade.created_by == user

      # Check if user is admin in this school
      UserSchoolRole.where(
        user: user,
        school: grade.school,
        role: "Admin",
        status: 0
      ).exists?
    end

    def validate_deletion_constraints
      if grade.learners.active.any?
        errors << "Cannot delete grade with active learners. Please graduate or transfer them first."
      end

      if grade.respond_to?(:learner_invitations) && grade.learner_invitations.pending.any?
        errors << "Cannot delete grade with pending learner invitations. Please cancel them first."
      end

      if grade.teacher_grade_assignments.active.any?
        errors << "Cannot delete grade with active teacher assignments. Please remove them first."
      end
    end

    def delete_grade
      # Soft delete - archive instead of hard delete
      if grade.update(status: 2) # archived
        Rails.logger.info "✅ Grade archived (soft deleted): #{grade.name} by #{user&.name || 'system'}"
        ServiceResult.new(success: true)
      else
        Rails.logger.error "❌ Failed to delete grade: #{grade.errors.full_messages.join(', ')}"
        ServiceResult.new(success: false, errors: grade.errors.full_messages)
      end
    end
  end
end
