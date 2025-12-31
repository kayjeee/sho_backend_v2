# app/controllers/api/v1/users_controller.rb
class Api::V1::UsersController < ApplicationController
  before_action :set_user, only: [
    :show,
    :update_roles,
    :schools,
    :add_school,
    :update_profile # ✅ added
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
    if @user.update(profile_params)
      render json: {
        success: true,
        data: { user: @user.to_api_hash }
      }, status: :ok
    else
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
  def profile_params
  user = params.require(:user)

  {
    name: [user[:first_name], user[:last_name]].compact.join(" "),
    phone_number: user[:phone]
  }.compact
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
