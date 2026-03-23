# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      wrap_parameters format: [:json]

      # Added :update_profile to the auth0 loading sequence
      before_action :load_user_by_auth0!, only: [:show, :schools, :update_roles, :add_school, :onboarding_status, :update_profile]
      before_action :load_user_by_path!, only: [:show_by_path, :schools_by_path, :onboarding_status_by_path]

      # =========================================================
      # POST /api/v1/users
      # =========================================================
      def create
        permitted = user_params.to_h
        log_debug "CREATE USER - Permitted Params", permitted

        result = UserServices::CreateUserService.call(user_params: permitted)

        if result.success?
          render_success(
            message: result.new_record ? 'User created successfully' : 'User already exists',
            data: { 
              user: result.user, 
              new_record: result.new_record 
            },
            status: result.new_record ? :created : :ok
          )
        else
          render_error("Failed to create user", result.errors)
        end
      rescue => e
        log_error "CREATE USER ERROR", { error: e.message, backtrace: e.backtrace.first(5) }
        render_error([e.message], status: :unprocessable_entity)
      end

      # =========================================================
      # GET /api/v1/users/show?auth0_id=xxx
      # =========================================================
      def show
        render_success(
          message: 'User retrieved successfully',
          data: { user: @user }
        )
      end

      # =========================================================
      # DEPRECATED: GET /api/v1/users/:auth0_id
      # =========================================================
      def show_by_path
        log_deprecated("/api/v1/users/:auth0_id", params[:auth0_id])
        render_success(
          message: 'User retrieved successfully',
          data: {
            user: @user,
            _deprecated: deprecated_payload("/api/v1/users/show?auth0_id=xxx")
          }
        )
      end

      # =========================================================
      # GET /api/v1/users/me
      # =========================================================
      def me
        auth0_id = extract_auth0_id_from_token || params[:auth0_id]
        return render_error("Authentication required", [], status: :unauthorized) if auth0_id.blank?

        # Use .where().first to avoid Mongoid exception
        user = User.where(auth0_id: auth0_id).first
        
        if user
          render_success(
            message: 'User retrieved successfully',
            data: { user: user }
          )
        else
          render_error("User not found", [], status: :not_found)
        end
      end

      # =========================================================
      # GET /api/v1/users/schools?auth0_id=xxx
      # =========================================================
      def schools
        fetch_schools_for(@user)
      end

      def schools_by_path
        log_deprecated("/api/v1/users/:auth0_id/schools", params[:auth0_id])
        fetch_schools_for(@user, deprecated_url: "/api/v1/users/schools?auth0_id=xxx")
      end

      # =========================================================
      # GET /api/v1/users/onboarding_status?auth0_id=xxx
      # =========================================================
      def onboarding_status
        status = @user.onboarding_status

        # Build a rich response that works for both legacy checks and the new parent flow
        if status
          data = status.to_api_hash
          data[:completed] = status.all_steps_completed?
        else
          data = { completed: false }
        end

        render_success(
          message: 'Onboarding status retrieved successfully',
          data: { onboarding_status: data }
        )
      end

      def onboarding_status_by_path
        log_deprecated("/api/v1/users/:auth0_id/onboarding_status", params[:auth0_id])
        
        status = @user.onboarding_status

        # Build a rich response that works for both legacy checks and the new parent flow
        if status
          data = status.to_api_hash
          data[:completed] = status.all_steps_completed?
        else
          data = { completed: false }
        end

        render_success(
          message: 'Onboarding status retrieved successfully',
          data: {
            onboarding_status: data,
            _deprecated: deprecated_payload("/api/v1/users/onboarding_status?auth0_id=xxx")
          }
        )
      end

      # =========================================================
      # PATCH /api/v1/users/update_profile?auth0_id=xxx
      # =========================================================
      def update_profile
        log_debug "UPDATE PROFILE PARAMS", profile_params

        if @user.update(profile_params)
          render_success(
            message: "Profile updated successfully",
            data: { user: serialize_user(@user) }
          )
        else
          render_error("Failed to update profile", @user.errors.full_messages)
        end
      end

      # =========================================================
      # PUT /api/v1/users/update_roles?auth0_id=xxx
      # =========================================================
      def update_roles
        roles = normalize_roles(params[:roles])
        return render_error("Roles parameter is required", [], status: :bad_request) if roles.empty?

        user = UserServices::UpdateRolesService.call(user: @user, roles: roles)
        
        if user
          render_success(
            message: 'Roles updated successfully',
            data: { user: user }
          )
        else
          render_error("Failed to update roles")
        end
      rescue => e
        log_error "UPDATE ROLES ERROR", { error: e.message }
        handle_exception(e, "Failed to update roles")
      end

      # =========================================================
      # POST /api/v1/users/add_school?auth0_id=xxx
      # =========================================================
      def add_school
        school_id = extract_school_id
        return render_error("schoolId parameter is required", [], status: :bad_request) if school_id.blank?

        result = UserServices::AddSchoolService.call(user: @user, school_id: school_id)
        
        if result&.user
          render_success(
            message: result.message || 'School added successfully',
            data: { user: result.user }
          )
        else
          render_error("Failed to add school to user")
        end
      rescue => e
        log_error "ADD SCHOOL ERROR", { error: e.message }
        handle_exception(e, "Failed to add school")
      end

      # =========================================================
      # INTERNAL DB ID ENDPOINTS (Keep for specific internal tools)
      # =========================================================
      def roles
        user = User.find(params[:id])
        render_success(
          message: 'Roles retrieved successfully',
          data: { roles: user.roles || [] }
        )
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      def add_role
        user = User.find(params[:id])
        role = params[:role]
        return render_error("Role parameter is required", [], status: :bad_request) if role.blank?

        updated_user = UserServices::AddRoleService.call(user: user, role: role)
        
        if updated_user
          render_success(
            message: 'Role added successfully',
            data: { user: updated_user }
          )
        else
          render_error("Failed to add role")
        end
      rescue Mongoid::Errors::DocumentNotFound
        render_error("User not found", [], status: :not_found)
      end

      def onboarding_required
        user = User.find(params[:id])
        status = user.onboarding_status || {}
        render_success(
          message: 'Onboarding status retrieved successfully',
          data: {
            required: !status[:completed] && !status['completed'],
            status: status
          }
        )
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      private

      # =======================================================
      # USER LOADING - FIXED VERSIONS
      # =======================================================
      def load_user_by_auth0!
        auth0_id = extract_auth0_id
        
        if auth0_id.present?
          # Use .where().first instead of find_by to avoid exception
          @user = User.where(auth0_id: auth0_id).first
        elsif params[:id].present?
          # Fallback to internal ID if it's a member route call
          @user = User.find(params[:id])
        end

        render_error(["User not found or auth0_id missing"], status: :not_found) unless @user
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      def load_user_by_path!
        id_param = params[:auth0_id]

        # 1. Try finding by auth0_id
        @user = User.where(auth0_id: id_param).first

        # 2. Fallback to finding by MongoDB _id
        if @user.nil?
          begin
            @user = User.find(id_param)
          rescue Mongoid::Errors::DocumentNotFound, BSON::ObjectId::Invalid
            @user = nil
          end
        end

        render_error(["User not found"], status: :not_found) unless @user
      end

      def extract_auth0_id
        params[:auth0_id] || params.dig(:user, :auth0_id)
      end

      def extract_auth0_id_from_token
        # JWT logic here
        nil
      end

      def extract_school_id
        params[:schoolId] || params[:school_id]
      end

      def normalize_roles(roles_param)
        Array.wrap(roles_param).compact.uniq
      end

      # =======================================================
      # STRONG PARAMETERS
      # =======================================================
      def user_params
        params.require(:user).permit(:auth0_id, :email, :name, :first_name, :last_name, :phone, :phone_number, :avatar_url, roles: [])
      end

      def profile_params
        # Accept both phone and phone_number for flexibility
        params.permit(:name, :email, :phone, :phone_number, :avatar_url, :bio, :timezone, :locale)
      end

      # =======================================================
      # SERIALIZATION
      # =======================================================
      def serialize_user(user)
        # Build hash with only fields that exist on the user model
        result = {
          id: user.id.to_s,
          auth0_id: user.auth0_id
        }
        
        # Add optional fields only if they exist on the model
        result[:name] = user.name if user.respond_to?(:name)
        result[:email] = user.email if user.respond_to?(:email)
        result[:phone] = user.phone if user.respond_to?(:phone)
        result[:phone_number] = user.phone_number if user.respond_to?(:phone_number)
        result[:avatar_url] = user.avatar_url if user.respond_to?(:avatar_url)
        result[:bio] = user.bio if user.respond_to?(:bio)
        result[:timezone] = user.timezone if user.respond_to?(:timezone)
        result[:locale] = user.locale if user.respond_to?(:locale)
        result[:roles] = user.roles if user.respond_to?(:roles)
        result[:created_at] = user.created_at if user.respond_to?(:created_at)
        result[:updated_at] = user.updated_at if user.respond_to?(:updated_at)
        
        result.compact
      end

      # =======================================================
      # HELPERS
      # =======================================================
      def fetch_schools_for(user, deprecated_url: nil)
        schools_data = UserServices::FetchSchoolsService.call(user: user)
        schools_array = schools_data.is_a?(Mongoid::Criteria) ? schools_data.to_a : Array(schools_data)
        
        data = {
          schools: schools_array
        }
        
        # Add deprecated info if this is a deprecated endpoint
        if deprecated_url
          data[:_deprecated] = deprecated_payload(deprecated_url)
        end
        
        message = schools_array.empty? ? 'No schools found' : 'Schools retrieved successfully'
        
        render_success(
          message: message,
          data: data
        )
      end

      def log_deprecated(endpoint, auth0_id)
        log_warning "DEPRECATED ENDPOINT", { endpoint: endpoint, auth0_id: auth0_id }
      end

      def deprecated_payload(migration_url)
        { 
          message: "Deprecated. Use #{migration_url}", 
          migration_guide: "/api/docs#migration" 
        }
      end


      def log_debug(action, data = {}); Rails.logger.debug "[Users] #{action}: #{data.inspect}"; end
      def log_warning(action, data = {}); Rails.logger.warn "⚠️ [Users] #{action}: #{data.inspect}"; end
      def log_error(action, data = {}); Rails.logger.error "🔥 [Users] #{action}: #{data.inspect}"; end
    end
  end
end