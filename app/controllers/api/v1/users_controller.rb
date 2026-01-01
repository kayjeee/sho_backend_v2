# app/controllers/api/v1/users_controller.rb
class Api::V1::UsersController < ApplicationController
  before_action :set_user, only: [
    :show,
    :update_roles,
    :schools,
    :add_school,
    :update_profile
  ]


  # POST /api/v1/users
  def create
    normalized_params = user_params.to_h
    roles = normalized_params[:roles]


    if roles.is_a?(String)
      normalized_params[:roles] = roles.split(',').map(&:strip).map(&:downcase)
    elsif roles.is_a?(Array)
      normalized_params[:roles] = roles.map(&:strip).map(&:downcase)
    else
      normalized_params[:roles] = []
    end


    service = UserServices::CreateUserService.new(user_params: normalized_params)
    result = service.call


    if result.success?
      render json: {
        success: true,
        data: { user: result.user }
      }, status: :created
    else
      render json: {
        success: false,
        errors: result.errors
      }, status: :unprocessable_entity
    end
  end


  # GET /api/v1/users/:id
  def show
    Rails.logger.debug "👁️ Showing user with auth0_id: #{@user.auth0_id}"


    render json: {
      success: true,
      data: { user: @user.to_api_hash }
    }, status: :ok
  end


  # GET /api/v1/users/:id/schools
  def schools
    schools = UserServices::FetchSchoolsService.new(user: @user).call


    if schools.any?
      school_data = schools.map do |school|
        {
          id: school.id,
          schoolName: school.schoolName || school[:schoolName],
          schoolEmail: school.schoolEmail || school[:schoolEmail],
          city: school.city,
          country: school.country,
          province: school.province,
          userEmail: school.user_email || school[:user_email],
          logo: school.logo
        }
      end


      render json: {
        success: true,
        data: { schools: school_data }
      }, status: :ok
    else
      Rails.logger.warn "⚠️ No schools found for user with auth0_id: #{@user.auth0_id}"


      render json: {
        success: false,
        error: "No schools found for this user."
      }, status: :not_found
    end
  end


  # PATCH /api/v1/users/:id/update_roles
  def update_roles
    result = UserServices::UpdateRolesService.call(
      user: @user,
      new_roles: params[:roles]
    )


    if result.success?
      render json: {
        success: true,
        data: { user: result.user }
      }, status: :ok
    else
      render json: {
        success: false,
        errors: result.errors
      }, status: :unprocessable_entity
    end
  end


  # POST /api/v1/users/:id/add_school
  def add_school
    result = UserServices::AddSchoolService.call(
      user: @user,
      school_id: params[:schoolId]
    )


    if result.success?
      render json: {
        success: true,
        message: result.message,
        data: { user: result.user }
      }, status: :ok
    else
      render json: {
        success: false,
        errors: result.errors
      }, status: :unprocessable_entity
    end
  end


  # PATCH /api/v1/users/:id/update_profile
  def update_profile
    Rails.logger.debug "📝 Updating profile for user: #{@user.auth0_id}"
    Rails.logger.debug "📦 Raw params: #{params.inspect}"
    Rails.logger.debug "🎯 Profile params: #{profile_params.inspect}"


    if @user.update(profile_params)
      Rails.logger.info "✅ Profile updated successfully"
      render json: {
        success: true,
        data: { user: @user.to_api_hash }
      }, status: :ok
    else
      Rails.logger.error "❌ Profile update failed: #{@user.errors.full_messages}"
      render json: {
        success: false,
        errors: @user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end


  private


  # Used ONLY for user creation
  def user_params
    Rails.logger.debug "🔒 Permitting user fields: name, email, auth0_id, roles, invitation_token"


    params.require(:user).permit(
      :name,
      :email,
      :auth0_id,
      :invitation_token,
      roles: []
    )
  end


  # Used ONLY for profile updates
  # ✨ NOW HANDLES BOTH FORMATS:
  #    1. { first_name, last_name, phone } from ProfileSetup component
  #    2. { name, phone_number } from ParentAPI transformation
  def profile_params
    Rails.logger.debug "🔧 Building profile_params from: #{params[:user].inspect}"
   
    # Extract user params
    user_params = params.require(:user)
   
    # Build update hash
    update_hash = {}
   
    # Handle name - THREE possible formats:
    # Format 1: first_name + last_name (from ProfileSetup directly)
    if user_params[:first_name].present? || user_params[:last_name].present?
      first = user_params[:first_name].to_s.strip
      last = user_params[:last_name].to_s.strip
      update_hash[:name] = [first, last].reject(&:blank?).join(" ")
      Rails.logger.debug "📛 Name from first_name + last_name: #{update_hash[:name]}"
    # Format 2: combined name (from ParentAPI transformation)
    elsif user_params[:name].present?
      update_hash[:name] = user_params[:name].strip
      Rails.logger.debug "📛 Name from combined name field: #{update_hash[:name]}"
    end
   
    # Handle phone number - TWO possible formats:
    # Format 1: phone_number (from ParentAPI transformation)
    if user_params[:phone_number].present?
      update_hash[:phone_number] = user_params[:phone_number].strip
      Rails.logger.debug "📞 Phone from phone_number field: #{update_hash[:phone_number]}"
    # Format 2: phone (from ProfileSetup directly)
    elsif user_params[:phone].present?
      update_hash[:phone_number] = user_params[:phone].strip
      Rails.logger.debug "📞 Phone from phone field: #{update_hash[:phone_number]}"
    end
   
    # Handle email if provided (though usually shouldn't change)
    if user_params[:email].present?
      update_hash[:email] = user_params[:email].strip
      Rails.logger.debug "📧 Email: #{update_hash[:email]}"
    end
   
    Rails.logger.debug "🎁 Final update_hash: #{update_hash.inspect}"
   
    update_hash
  end


  def set_user
    Rails.logger.debug "🔍 Looking up user by auth0_id: #{params[:id]}"


    @user = User.find_by(auth0_id: params[:id])


    unless @user
      Rails.logger.warn "❌ User not found with auth0_id: #{params[:id]}"
      render json: {
        success: false,
        error: "User not found"
      }, status: :not_found
    end
  end
end