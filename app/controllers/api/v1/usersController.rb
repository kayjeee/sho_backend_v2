class Api::V1::UsersController < ApplicationController
  # Added :update_profile to the set_user filter array
  before_action :set_user, only: [:show, :update_roles, :schools, :add_school, :update_profile]

  # POST /api/v1/users
  def create
    service = UserServices::CreateUserService.new(user_params: user_params)
    result = service.call

    if result.success?
      render json: { success: true, data: { user: result.user } }, status: :created
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/:auth0_id
  def show
    Rails.logger.debug "👁️ Showing user with auth0_id: #{@user.auth0_id}"

    primary_school = UserServices::FetchSchoolsService.new(user: @user).call.first
    primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)

    user_data = @user.as_json
    user_data['onboarding_completed'] = @user.onboarding_completed
    user_data['onboardingCompleted'] = @user.onboarding_completed
    user_data['primary_school_name'] = primary_school_name
    user_data['primarySchoolName'] = primary_school_name
    user_data['school_name'] = primary_school_name
    user_data['schoolName'] = primary_school_name

    render json: { success: true, data: { user: user_data } }, status: :ok
  end

  # PATCH /api/v1/users/:auth0_id/update_profile
  def update_profile
    Rails.logger.debug "✏️ Updating profile for user with auth0_id: #{@user.auth0_id}"
    
    if @user.update(user_params)
      render json: { success: true, data: { user: @user } }, status: :ok
    else
      render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/:auth0_id/schools
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
          userEmail: school.user_email || school[:user_email]
        }
      end

      render json: { success: true, data: { schools: school_data } }, status: :ok
    else
      Rails.logger.warn "⚠️ No schools found for user with auth0_id: #{@user.auth0_id}"
      render json: { success: false, error: "No schools found for this user." }, status: :not_found
    end
  end

  # PUT /api/v1/users/:auth0_id/update_roles
  def update_roles
    result = UserServices::UpdateRolesService.call(user: @user, new_roles: params[:roles])

    if result.success?
      render json: { success: true, data: { user: result.user } }, status: :ok
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/users/:auth0_id/add_school
  def add_school
    result = UserServices::AddSchoolService.call(user: @user, school_id: params[:schoolId])

    if result.success?
      render json: {
        success: true,
        message: result.message,
        data: { user: result.user }
      }, status: :ok
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end

  private

  def user_params
    Rails.logger.debug "🔒 Permitting user fields: name, email, auth0_id, roles"
    params.require(:user).permit(:name, :email, :auth0_id, roles: [])
  end

  def set_user
    lookup_id = params[:auth0_id] || params[:id]
    Rails.logger.debug "🔍 Looking up user by auth0_id: #{lookup_id}"
    @user = User.find_by(auth0_id: lookup_id)
    
    unless @user
      Rails.logger.warn "❌ User not found with auth0_id: #{lookup_id}"
      render json: { success: false, error: "User not found" }, status: :not_found
    end
  end
end
