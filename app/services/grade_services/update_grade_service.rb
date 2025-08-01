# app/services/grade_services/update_grade_service.rb
class GradeServices::UpdateGradeService
  attr_reader :grade, :user, :grade_params, :errors

  def initialize(grade:, user:, grade_params:)
    @grade = grade
    @user = user
    @grade_params = grade_params
    @errors = []
  end

  def call
    validate_permissions
    return { success: false, errors: @errors } if @errors.any?

    update_grade
  end

  private

  def validate_permissions
    unless can_update_grade?
      @errors << "You don't have permission to update this grade"
    end
  end

  def can_update_grade?
    return true if user.roles.include?('Admin')
    return true if grade.created_by == user
    
    # Check if user is admin in this school
    user_role = UserSchoolRole.find_by(
      user: user, 
      school: grade.school, 
      role: 'Admin', 
      status: 0
    )
    
    user_role.present?
  end

  def update_grade
    # Handle status changes specially
    if grade_params[:status] && grade_params[:status].to_i != grade.status
      return handle_status_change(grade_params[:status].to_i)
    end

    if grade.update(grade_params)
      Rails.logger.info "✅ Grade updated successfully: #{grade.name} by #{user.name}"
      { success: true, grade: grade }
    else
      Rails.logger.error "❌ Failed to update grade: #{grade.errors.full_messages.join(', ')}"
      { success: false, errors: grade.errors.full_messages }
    end
  end

  def handle_status_change(new_status)
    case new_status
    when 1 # inactive
      return deactivate_grade
    when 2 # archived
      return archive_grade
    when 0 # active
      return activate_grade
    else
      grade.update(grade_params)
      { success: true, grade: grade }
    end
  end

  def deactivate_grade
    # Check if grade has active learners
    if grade.learners.active.any?
      return { success: false, errors: ["Cannot deactivate grade with active learners"] }
    end

    grade.update(status: 1)
    { success: true, grade: grade }
  end

  def archive_grade
    # Archive grade only if no active learners
    if grade.learners.active.any?
      return { success: false, errors: ["Cannot archive grade with active learners"] }
    end

    grade.update(status: 2)
    { success: true, grade: grade }
  end

  def activate_grade
    grade.update(status: 0)
    { success: true, grade: grade }
  end
end