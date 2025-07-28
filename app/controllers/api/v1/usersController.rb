class Api::V1::UsersController < ApplicationController
  before_action :set_user, only: [:show, :update_roles, :schools, :add_school]
  
  def create
    result = UserServices::CreateUserService.call(user_params: user_params)
    
    if result.success?
      render json: { success: true, data: { user: result.user } }, status: :created
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end
  
  def show
    Rails.logger.debug "👁️‍🗨️ UsersController#show: Showing user #{@user.auth0_id}"
    render json: { success: true, data: { user: @user } }, status: :ok
  end
  
  def schools
    schools = UserServices::FetchSchoolsService.new(user: @user).call
    
    if schools.any?
render json: {
  success: true,
  data: {
    schools: schools.map do |school|
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
  }
}, status: :ok

    else
      Rails.logger.warn "⚠️ UsersController#schools: No schools found for user #{@user.auth0_id}"
      render json: { success: false, error: "No schools found for this user." }, status: :not_found
    end
  end
  
  def update_roles
    result = UserServices::UpdateRolesService.call(user: @user, new_roles: params[:roles])
    
    if result.success?
      render json: { success: true, data: { user: result.user } }, status: :ok
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end
  
  def add_school
    result = UserServices::AddSchoolService.call(user: @user, school_id: params[:schoolId])
    
    if result.success?
      render json: { success: true, message: result.message, data: { user: result.user } }, status: :ok
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end
  
  private
  
  def user_params
    Rails.logger.debug "🔒 UsersController#user_params: Permitting user fields"
    params.require(:user).permit(:name, :email, :auth0_id, roles: [])
  end
  
  def set_user
    Rails.logger.debug "🔍 UsersController#set_user: Finding user with auth0_id #{params[:id]}"
    @user = User.find_by(auth0_id: params[:id])
    unless @user
      Rails.logger.warn "❌ UsersController#set_user: User not found with auth0_id #{params[:id]}"
      render json: { success: false, error: "User not found" }, status: :not_found
    end
  end
end