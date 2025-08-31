# app/controllers/concerns/onboarding_authorization.rb
module OnboardingAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_onboarding_access!
    # Users can access their own onboarding status
    return if current_user == @target_user
    
    # Super admins can access any user's onboarding status
    return if current_user.roles.include?('super_admin')
    
    # Admins can access onboarding status of users in their schools
    if current_user.roles.include?('admin')
      shared_schools = current_user.schools & @target_user.schools
      return if shared_schools.any?
    end
    
    # Teachers can view (but not modify) onboarding status of users in their schools
    if current_user.roles.include?('teacher') && request.get?
      shared_schools = current_user.schools & @target_user.schools
      return if shared_schools.any?
    end
    
    render json: {
      success: false,
      message: "Unauthorized to access onboarding status",
      error_code: "ONBOARDING_ACCESS_DENIED"
    }, status: :forbidden
  end

  def authorize_onboarding_modification!
    # Users can modify their own onboarding status
    return if current_user == @target_user
    
    # Super admins can modify any user's onboarding status
    return if current_user.roles.include?('super_admin')
    
    # Admins can modify onboarding status of users in their schools
    if current_user.roles.include?('admin')
      shared_schools = current_user.schools & @target_user.schools
      return if shared_schools.any?
    end
    
    render json: {
      success: false,
      message: "Unauthorized to modify onboarding status",
      error_code: "ONBOARDING_MODIFICATION_DENIED"
    }, status: :forbidden
  end
end