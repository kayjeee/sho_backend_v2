class Api::V1::UsersController < ApplicationController
  before_action :set_user, only: [:show, :update_roles, :schools, :add_school, :update_profile, :add_role]
  before_action :set_user_by_path, only: [:show_by_path, :schools_by_path, :onboarding_status_by_path, :onboarding_status]

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

  # POST /api/v1/users/:id/add_role
  def add_role
    role_to_add = (params[:role] || params[:role_name]).to_s.strip

    if role_to_add.blank?
      return render json: { success: false, error: "Role is required" }, status: :bad_request
    end

    @user.add_to_set(roles: role_to_add)

    render json: {
      success: true,
      roles: @user.reload.roles
    }, status: :ok
  rescue => e
    render_exception("UsersController#add_role", e)
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

  # Deprecated path compatibility routes
  def show_by_path
    show
  end

  def schools_by_path
    schools
  end

  def onboarding_status
    onboarding_status_by_path
  end

  def onboarding_status_by_path
    @user.ensure_onboarding_status if @user.respond_to?(:ensure_onboarding_status)
    status = @user.onboarding_status

    if status
      data = status.as_json
      data['onboarding_completed'] = @user.onboarding_completed
      data['onboardingCompleted'] = @user.onboarding_completed

      primary_school = UserServices::FetchSchoolsService.new(user: @user).call.first
      primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)
      data['primary_school_name'] = primary_school_name
      data['primarySchoolName'] = primary_school_name
      data['school_name'] = primary_school_name
      data['schoolName'] = primary_school_name
    else
      data = { completed: false, onboardingCompleted: false, onboarding_completed: false }
    end

    render json: {
      success: true,
      data: data,
      message: "Fetched onboarding status"
    }
  end

  private

  def user_params
    Rails.logger.debug "🔒 Permitting user fields: name, email, auth0_id, roles, department, position, title, first_name, surname"
    source = params[:user].presence || params
    source.permit(:name, :email, :auth0_id, :department, :position, :title, :first_name, :surname, roles: [])
  end

  def set_user
    lookup_id = params[:auth0_id] || params[:id]

    # If the URL was users/show (meaning Rails routed to show action and params[:auth0_id] is "show")
    if lookup_id == "show"
      lookup_id = params[:real_auth0_id] || request.query_parameters['auth0_id'] || params[:user_auth0_id]

      if lookup_id.blank? && request.headers['Authorization'].present?
        begin
          authorize
          if @decoded_token && @decoded_token.respond_to?(:token) && @decoded_token.token.is_a?(Array)
            lookup_id = @decoded_token.token[0]['sub']
          end
        rescue => e
          Rails.logger.error "⚠️ Could not authorize token in fallback set_user: #{e.message}"
        end
      end
    end

    if lookup_id.blank?
      render json: { success: false, error: "User not found", message: "User identifier is required" }, status: :not_found
      return
    end

    Rails.logger.debug "🔍 Looking up user by identifier: #{lookup_id}"

    # Try lookup by Mongo _id first if BSON ObjectId format
    if BSON::ObjectId.legal?(lookup_id.to_s)
      @user = User.where(_id: BSON::ObjectId.from_string(lookup_id.to_s)).first
    end

    # Fallback lookup by auth0_id
    @user ||= User.find_by(auth0_id: lookup_id.to_s)

    unless @user
      Rails.logger.warn "❌ User not found with identifier: #{lookup_id}"
      render json: { success: false, error: "User not found" }, status: :not_found
    end
  rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
    render json: { success: false, error: "User not found" }, status: :not_found
  rescue StandardError => e
    Rails.logger.error "🔥 Unexpected error in set_user: #{e.message}"
    render json: { success: false, error: "User not found" }, status: :not_found
  end

  def set_user_by_path
    lookup_id = params[:auth0_id]
    if lookup_id.blank?
      render json: { success: false, error: "User not found", message: "User identifier is required" }, status: :not_found
      return
    end

    Rails.logger.debug "🔍 Looking up user by path-based auth0_id: #{lookup_id}"
    @user = User.find_by(auth0_id: lookup_id)

    unless @user
      Rails.logger.warn "❌ User not found with auth0_id: #{lookup_id}"
      render json: { success: false, error: "User not found" }, status: :not_found
    end
  rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
    render json: { success: false, error: "User not found" }, status: :not_found
  rescue StandardError => e
    Rails.logger.error "🔥 Unexpected error in set_user_by_path: #{e.message}"
    render json: { success: false, error: "User not found" }, status: :not_found
  end

  def render_exception(context, exception)
    cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
    Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
    render json: { success: false, error: exception.message }, status: :internal_server_error
  end
end
