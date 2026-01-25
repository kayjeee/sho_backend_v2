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
            { user: result.user, new_record: result.new_record },
            status: result.new_record ? :created : :ok
          )
        else
          render_error(result.errors, status: :unprocessable_entity)
        end
      rescue => e
        log_error "CREATE USER ERROR", { error: e.message, backtrace: e.backtrace.first(5) }
        render_error([e.message], status: :unprocessable_entity)
      end

      # =========================================================
      # GET /api/v1/users/show?auth0_id=xxx
      # =========================================================
      def show
        render_success(user: @user)
      end

      # =========================================================
      # DEPRECATED: GET /api/v1/users/:auth0_id
      # =========================================================
      def show_by_path
        log_deprecated("/api/v1/users/:auth0_id", params[:auth0_id])
        render_success(
          { user: @user },
          _deprecated: deprecated_payload("/api/v1/users/show?auth0_id=xxx")
        )
      end

      # =========================================================
      # GET /api/v1/users/me
      # =========================================================
      def me
        auth0_id = extract_auth0_id_from_token || params[:auth0_id]
        return render_error(["Authentication required"], status: :unauthorized) if auth0_id.blank?

        user = User.find_by(auth0_id: auth0_id)
        user ? render_success(user: user) : render_error(["User not found"], status: :not_found)
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
        status = @user.onboarding_status || {}
        render_success(onboarding_status: status, completed: status[:completed] || false)
      end

      def onboarding_status_by_path
        log_deprecated("/api/v1/users/:auth0_id/onboarding_status", params[:auth0_id])
        status = @user.onboarding_status || {}
        render_success(
          { onboarding_status: status, completed: status[:completed] || false },
          _deprecated: deprecated_payload("/api/v1/users/onboarding_status?auth0_id=xxx")
        )
      end

      # =========================================================
      # PATCH /api/v1/users/update_profile?auth0_id=xxx 
      # OR PATCH /api/v1/users/:id/update_profile
      # =========================================================
      def update_profile
        # @user is loaded via load_user_by_auth0! before_action
        log_debug "UPDATE_PROFILE - Received params", params
        
        # Extract permitted parameters
        permitted_params = profile_params
        
        log_debug "UPDATE_PROFILE - Permitted params", permitted_params
        
        # Try to update the user
        if @user.update(permitted_params)
          log_debug "UPDATE_PROFILE - Success", { user_id: @user.id, updated_fields: permitted_params.keys }
          
          # Simple render without the problematic render_success method
          render json: {
            success: true,
            data: { 
              user: {
                id: @user.id.to_s,
                auth0_id: @user.auth0_id,
                name: @user.name,
                email: @user.email,
                phone: @user.try(:phone) || @user.try(:phone_number) || nil,
                phone_number: @user.try(:phone_number) || @user.try(:phone) || nil,
                roles: @user.roles || [],
                created_at: @user.created_at,
                updated_at: @user.updated_at
              }
            },
            message: "Profile updated successfully"
          }, status: :ok
        else
          log_error "UPDATE_PROFILE - Failed", { user_id: @user.id, errors: @user.errors.full_messages }
          render_error(@user.errors.full_messages, status: :unprocessable_entity)
        end
      end

      # =========================================================
      # PUT /api/v1/users/update_roles?auth0_id=xxx
      # =========================================================
      def update_roles
        roles = normalize_roles(params[:roles])
        return render_error(["Roles parameter is required"], status: :bad_request) if roles.empty?

        user = UserServices::UpdateRolesService.call(user: @user, roles: roles)
        user ? render_success(user: user) : render_error(["Failed to update roles"], status: :unprocessable_entity)
      rescue => e
        log_error "UPDATE ROLES ERROR", { error: e.message }
        render_error(["Failed to update roles: #{e.message}"], status: :unprocessable_entity)
      end

      # =========================================================
      # POST /api/v1/users/add_school?auth0_id=xxx
      # =========================================================
      def add_school
        school_id = extract_school_id
        return render_error(["schoolId parameter is required"], status: :bad_request) if school_id.blank?

        result = UserServices::AddSchoolService.call(user: @user, school_id: school_id)
        if result&.user
          render_success(message: result.message || "School added successfully", user: result.user)
        else
          render_error(["Failed to add school to user"], status: :unprocessable_entity)
        end
      rescue => e
        log_error "ADD SCHOOL ERROR", { error: e.message }
        render_error(["Failed to add school: #{e.message}"], status: :unprocessable_entity)
      end

      # =========================================================
      # INTERNAL DB ID ENDPOINTS (Keep for specific internal tools)
      # =========================================================
      def roles
        user = User.find(params[:id])
        render_success(roles: user.roles || [])
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      def add_role
        user = User.find(params[:id])
        role = params[:role]
        return render_error(["Role parameter is required"], status: :bad_request) if role.blank?

        updated_user = UserServices::AddRoleService.call(user: user, role: role)
        updated_user ? render_success(user: updated_user) : render_error(["Failed to add role"], status: :unprocessable_entity)
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      def onboarding_required
        user = User.find(params[:id])
        status = user.onboarding_status || {}
        render_success(required: !status[:completed], status: status)
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      private

      # =======================================================
      # USER LOADING
      # =======================================================
      def load_user_by_auth0!
        auth0_id = extract_auth0_id
        
        if auth0_id.present?
          # Try finding by Auth0 ID first
          @user = User.find_by(auth0_id: auth0_id)
        elsif params[:id].present?
          # Fallback to internal ID if it's a member route call
          @user = User.find(params[:id])
        end

        render_error(["User not found or auth0_id missing"], status: :not_found) unless @user
      rescue Mongoid::Errors::DocumentNotFound
        render_error(["User not found"], status: :not_found)
      end

      def load_user_by_path!
        @user = User.find_by(auth0_id: params[:auth0_id])
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
        # ✅ FIXED: Added :phone_number to the permitted parameters
        params.permit(:name, :first_name, :last_name, :email, :phone, :phone_number, :avatar_url, :bio, :timezone, :locale)
      end

      # =======================================================
      # HELPERS
      # =======================================================
      def fetch_schools_for(user, deprecated_url: nil)
        schools_data = UserServices::FetchSchoolsService.call(user: user)
        schools_array = schools_data.is_a?(Mongoid::Criteria) ? schools_data.to_a : Array(schools_data)
        payload = schools_array.empty? ? { schools: [], message: "No schools found" } : { schools: schools_array }
        payload.merge!(_deprecated: deprecated_payload(deprecated_url)) if deprecated_url
        render_success(payload)
      end

      def log_deprecated(endpoint, auth0_id)
        log_warning "DEPRECATED ENDPOINT", { endpoint: endpoint, auth0_id: auth0_id }
      end

      def deprecated_payload(migration_url)
        { message: "Deprecated. Use #{migration_url}", migration_guide: "/api/docs#migration" }
      end

      def render_success(payload = {}, status: :ok)
        # ✅ FIXED: Ensure we're handling the payload correctly
        # If payload is already a hash with keys like :user, :message, etc., use it as is
        # Otherwise wrap it in a hash
        data = payload.is_a?(Hash) && payload.keys.any? { |k| k.is_a?(Symbol) || k.is_a?(String) } ? payload : { data: payload }
        
        render json: { success: true }.merge(data), status: status
      end

      def render_error(errors, status: :bad_request)
        render json: { success: false, errors: Array.wrap(errors).compact }, status: status
      end

      def log_debug(action, data = {}); Rails.logger.debug "[Users] #{action}: #{data.inspect}"; end
      def log_warning(action, data = {}); Rails.logger.warn "⚠️ [Users] #{action}: #{data.inspect}"; end
      def log_error(action, data = {}); Rails.logger.error "🔥 [Users] #{action}: #{data.inspect}"; end
    end
  end
end