# =============================================================================
# API::V1::USERS CONTROLLER
# =============================================================================
# This controller handles all user-related API operations for version 1 of the API.
# It provides endpoints for creating users, viewing user details, managing user roles,
# and retrieving or adding schools associated with a user.
#
# Routes handled:
# - POST    /api/v1/users                -> create
# - GET     /api/v1/users/:id            -> show
# - GET     /api/v1/users/:id/schools    -> schools
# - PATCH   /api/v1/users/:id/roles      -> update_roles
# - PATCH   /api/v1/users/:id/add_school -> add_school
# =============================================================================

class Api::V1::UsersController < ApplicationController

  # =============================================================================
  # BEFORE ACTIONS
  # =============================================================================
  before_action :set_user, only: [:show, :update_roles, :schools, :add_school]

  # =============================================================================
  # CREATE USER ACTION
  # =============================================================================
  def create
    Rails.logger.debug "📥 UsersController#create: Received params: #{params.inspect}"

    user = User.new(user_params)

    if user.save
      Rails.logger.info "✅ UsersController#create: User created successfully - ID: #{user.id}"
      render json: { success: true, data: { user: user } }, status: :created
    else
      Rails.logger.error "❌ UsersController#create: Failed to create user. Errors: #{user.errors.full_messages.join(', ')}"
      render json: { success: false, errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # =============================================================================
  # SHOW USER ACTION
  # =============================================================================
  def show
    Rails.logger.debug "👁️‍🗨️ UsersController#show: Showing user #{@user.auth0_id}"
    render json: { success: true, data: { user: @user } }, status: :ok
  end

  # =============================================================================
  # GET USER SCHOOLS ACTION
  # =============================================================================
 def schools
  Rails.logger.debug "🏫 UsersController#schools: Fetching schools for user #{@user.auth0_id}"

  school_ids = Array(@user.school_ids).map(&:to_s)
  schools = School.where(:_id.in => school_ids.map { |id| BSON::ObjectId.from_string(id) })

  if schools.any?
    Rails.logger.info "✅ UsersController#schools: Found #{schools.count} school(s) for user #{@user.auth0_id}"
    render json: {
      success: true,
      data: {
        schools: schools.map { |school| school.as_json(only: [:id, :school_name, :school_email, :city, :country]) }
      }
    }, status: :ok
  else
    Rails.logger.warn "⚠️ UsersController#schools: No schools found for user #{@user.auth0_id}"
    render json: { success: false, error: "No schools found for this user." }, status: :not_found
  end
 end


  # =============================================================================
  # UPDATE USER ROLES ACTION
  # =============================================================================
  def update_roles
    new_roles = params[:roles] || []
    Rails.logger.debug "🛠️ UsersController#update_roles: Adding roles #{new_roles.inspect} to user #{@user.auth0_id}"

    @user.roles = (@user.roles + new_roles).uniq

    if @user.save
      Rails.logger.info "✅ UsersController#update_roles: Roles updated for user #{@user.auth0_id}"
      render json: { success: true, data: { user: @user } }, status: :ok
    else
      Rails.logger.error "❌ UsersController#update_roles: Failed to update roles. Errors: #{@user.errors.full_messages.join(', ')}"
      render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # =============================================================================
  # ADD SCHOOL TO USER ACTION
  # =============================================================================
  def add_school
    school_id = params[:schoolId].to_s.strip
    Rails.logger.debug "➕ UsersController#add_school: Adding school #{school_id} to user #{@user.auth0_id}"

    if school_id.blank?
      Rails.logger.warn "⚠️ UsersController#add_school: Missing schoolId in request."
      return render json: { success: false, error: "Missing schoolId parameter." }, status: :bad_request
    end

    result = @user.add_school(school_id)

    if result
      Rails.logger.info "✅ UsersController#add_school: School #{school_id} added to user #{@user.auth0_id}"
      render json: { success: true, message: "School added successfully.", data: { user: @user } }, status: :ok
    else
      Rails.logger.error "❌ UsersController#add_school: Failed to add school #{school_id} - #{@user.errors.full_messages.join(', ')}"
      render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # =============================================================================
  # PRIVATE METHODS
  # =============================================================================
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
