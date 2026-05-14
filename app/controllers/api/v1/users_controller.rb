# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      wrap_parameters format: [:json]

      # ── Audited against actual action methods in this file ──────────────────
      # load_user_by_auth0! guards:  show, schools, onboarding_status,
      #                              update_profile, heartbeat
      # load_user_by_path! guards:  show_by_path, schools_by_path
      #
      # All phantom actions removed (update_roles, add_school,
      # onboarding_status_by_path) — routed but never implemented here.
      # ────────────────────────────────────────────────────────────────────────

      before_action :load_user_by_auth0!,
                    only: %i[
                      show
                      schools
                      onboarding_status
                      update_profile
                    ]

      before_action :load_user_flexibly!,
                    only: %i[heartbeat]

      before_action :load_user_by_path!,
                    only: %i[
                      show_by_path
                      schools_by_path
                    ]

      # =========================================================
      # POST /api/v1/users
      # =========================================================
      def create
        permitted = user_params.to_h

        log_debug "CREATE USER - Permitted Params", permitted

        result = UserServices::CreateUserService.call(
          user_params: permitted
        )

        if result.success?
          render_success(
            message: result.new_record ?
              "User created successfully" :
              "User already exists",
            data: {
              user:       result.user,
              new_record: result.new_record
            },
            status: result.new_record ? :created : :ok
          )
        else
          render_error("Failed to create user", result.errors)
        end
      rescue => e
        log_error "CREATE USER ERROR", {
          error:     e.message,
          backtrace: e.backtrace.first(5)
        }
        render_error([e.message], status: :unprocessable_entity)
      end

      # =========================================================
      # GET /api/v1/users/show?auth0_id=xxx
      # =========================================================
      def show
        render_success(
          message: "User retrieved successfully",
          data:    { user: @user }
        )
      end

      # =========================================================
      # POST /api/v1/users/:auth0_id/heartbeat
      # =========================================================
      # Returns head :ok (no body). The frontend must NOT call
      # response.json() on this endpoint — use a raw fetch or
      # check response.status only.
      def heartbeat
        @user&.touch_last_seen!
        head :ok
      rescue => e
        log_error "HEARTBEAT ERROR", {
          error:    e.message,
          user_id: heartbeat_user_id
        }
        head :ok # always 200 — heartbeat must never surface errors
      end

      # =========================================================
      # DEPRECATED: GET /api/v1/users/:auth0_id
      # =========================================================
      def show_by_path
        log_deprecated("/api/v1/users/:auth0_id", params[:auth0_id])

        render_success(
          message: "User retrieved successfully",
          data: {
            user:        @user,
            _deprecated: deprecated_payload("/api/v1/users/show?auth0_id=xxx")
          }
        )
      end

      # =========================================================
      # GET /api/v1/users/me
      # =========================================================
      def me
        auth0_id =
          extract_auth0_id_from_token ||
          params[:auth0_id]

        return render_error(
          "Authentication required", [], status: :unauthorized
        ) if auth0_id.blank?

        user = User.where(auth0_id: auth0_id).first

        if user
          render_success(
            message: "User retrieved successfully",
            data:    { user: user }
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

      # =========================================================
      # DEPRECATED: GET /api/v1/users/:auth0_id/schools
      # =========================================================
      def schools_by_path
        log_deprecated(
          "/api/v1/users/:auth0_id/schools",
          params[:auth0_id]
        )
        fetch_schools_for(
          @user,
          deprecated_url: "/api/v1/users/schools?auth0_id=xxx"
        )
      end

      # =========================================================
      # GET /api/v1/users/onboarding_status?auth0_id=xxx
      # =========================================================
      def onboarding_status
        status = @user.onboarding_status

        data =
          if status
            payload = status.to_api_hash
            payload[:completed] = status.all_steps_completed?
            payload
          else
            { completed: false }
          end

        render_success(
          message: "Onboarding status retrieved successfully",
          data:    { onboarding_status: data }
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
            data:    { user: serialize_user(@user) }
          )
        else
          render_error(
            "Failed to update profile",
            @user.errors.full_messages
          )
        end
      end

      private

      # =======================================================
      # USER LOADING
      # =======================================================

      # Resolves @user from:
      #   1. auth0_id param matching User#auth0_id  (e.g. "google-oauth2|123")
      #   2. auth0_id param that is actually a BSON ObjectId (e.g. "69c113...")
      #      — happens when the frontend passes the DB id via the :auth0_id
      #      route segment (deprecated but still in use on some pages)
      #   3. params[:id] as a BSON ObjectId fallback
      def load_user_by_auth0!
        raw = extract_auth0_id

        @user =
          if raw.present?
            # Primary: treat as an Auth0 ID string
            found = User.where(auth0_id: raw).first

            # Fallback: raw value looks like a MongoDB ObjectId — try a direct
            # document lookup. This covers GET /api/v1/users/:mongo_id calls
            # that still route through this action.
            if found.nil? && bson_object_id?(raw)
              begin
                found = User.find(raw)
              rescue Mongoid::Errors::DocumentNotFound,
                     BSON::ObjectId::Invalid
                found = nil
              end
            end

            found
          elsif params[:id].present?
            begin
              User.find(params[:id])
            rescue Mongoid::Errors::DocumentNotFound,
                   BSON::ObjectId::Invalid
              nil
            end
          end

        render_error(
          ["User not found or auth0_id missing"],
          status: :not_found
        ) unless @user
      end

      def load_user_by_path!
        id_param = params[:auth0_id]

        # Try auth0_id string first
        @user = User.where(auth0_id: id_param).first

        # Fallback to ObjectId if not found
        if @user.nil?
          begin
            @user = User.find(id_param)
          rescue Mongoid::Errors::DocumentNotFound,
                 BSON::ObjectId::Invalid
            @user = nil
          end
        end

        render_error(["User not found"], status: :not_found) unless @user
      end

      def load_user_flexibly!
        raw = heartbeat_user_id

        @user = User.where(auth0_id: raw).first
        @user ||= User.find(raw) if bson_object_id?(raw)

        return if @user

        log_warning(
          "HEARTBEAT USER NOT FOUND",
          { user_id: raw }
        )
      rescue Mongoid::Errors::DocumentNotFound,
             BSON::Error::InvalidObjectId,
             BSON::ObjectId::Invalid => e
        log_warning(
          "HEARTBEAT USER LOOKUP FAILED",
          { user_id: raw, error: e.message }
        )
      end

      # =======================================================
      # HELPERS
      # =======================================================
      def extract_auth0_id
        params[:auth0_id] ||
          params.dig(:user, :auth0_id)
      end

      def heartbeat_user_id
        params[:id] ||
          params[:auth0_id] ||
          params.dig(:user, :auth0_id)
      end

      def extract_auth0_id_from_token
        # Extend when token-based auth0_id extraction is needed
        nil
      end

      # Returns true if the string looks like a 24-char hex MongoDB ObjectId.
      # Used to decide whether to attempt User.find(raw) as a fallback.
      def bson_object_id?(str)
        str.to_s.match?(/\A[0-9a-f]{24}\z/i)
      end

      def normalize_roles(roles_param)
        Array.wrap(roles_param).compact.uniq
      end

      # =======================================================
      # STRONG PARAMETERS
      # =======================================================
      def user_params
        params.require(:user).permit(
          :auth0_id,
          :email,
          :name,
          :first_name,
          :last_name,
          :phone,
          :phone_number,
          :avatar_url,
          roles: []
        )
      end

      def profile_params
        params.permit(
          :name,
          :email,
          :phone,
          :phone_number,
          :avatar_url,
          :bio,
          :timezone,
          :locale
        )
      end

      # =======================================================
      # SERIALIZATION
      # =======================================================
      def serialize_user(user)
        {
          id:           user.id.to_s,
          auth0_id:     user.auth0_id,
          name:         user.name,
          email:        user.email,
          phone:        user.phone,
          phone_number: user.phone_number,
          avatar_url:   user.try(:avatar_url),
          bio:          user.try(:bio),
          timezone:     user.try(:timezone),
          locale:       user.try(:locale),
          roles:        user.roles,
          created_at:   user.created_at,
          updated_at:   user.updated_at
        }.compact
      end

      # =======================================================
      # LOGGING
      # =======================================================
      def log_debug(action, data = {})
        Rails.logger.debug "[Users] #{action}: #{data.inspect}"
      end

      def log_warning(action, data = {})
        Rails.logger.warn "⚠️ [Users] #{action}: #{data.inspect}"
      end

      def log_error(action, data = {})
        Rails.logger.error "🔥 [Users] #{action}: #{data.inspect}"
      end

      def log_deprecated(endpoint, auth0_id)
        log_warning(
          "DEPRECATED ENDPOINT",
          { endpoint: endpoint, auth0_id: auth0_id }
        )
      end

      def deprecated_payload(migration_url)
        {
          message:         "Deprecated. Use #{migration_url}",
          migration_guide: "/api/docs#migration"
        }
      end
    end
  end
end
