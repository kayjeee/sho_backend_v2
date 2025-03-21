class Api::V1::UsersController < ApplicationController
  before_action :set_user, only: [:show, :update_roles, :schools]

  def create
    user = User.new(user_params)

    if user.save
      render json: { success: true, data: user }, status: :created
    else
      render json: { success: false, errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def schools
    user_id = @user.auth0_id
    schools = School.where(user_id: user_id)

    if schools.any?
      render json: { success: true, data: { schools: schools } }, status: :ok
    else
      render json: { success: false, error: "No schools found for this user." }, status: :not_found
    end
  end  

  def show
    render json: { success: true, data: @user }, status: :ok
  end

  def update_roles
    new_roles = params[:roles] || []
    @user.roles = (@user.roles + new_roles).uniq
  
    if @user.save
      render json: { success: true, data: @user }, status: :ok
    else
      render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end
  

  private

  def user_params
    params.require(:user).permit(:name, :email, :auth0_id, roles: [])
  end

  def set_user
    @user = User.find_by(auth0_id: params[:id])
    unless @user
      Rails.logger.warn("User with auth0_id: #{params[:id]} not found")
      render json: { success: false, error: "User not found" }, status: :not_found
    end
  end
end
