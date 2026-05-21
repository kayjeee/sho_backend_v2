# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      wrap_parameters format: [:json]

      # ── before_action guard map ──────────────────────────────────────────────
      # load_user_by_auth0!  →  show, schools, onboarding_status,
      #                         update_profile
      # load_user_by_path!   →  show_by_path, schools_by_path
      # heartbeat loads its own user (supports both auth0_id and ObjectId)
      # ────────────────────────────────────────────────────────────────────────

      before_action :load_user_by_auth0!,
                    only: %i[
                      show
                      schools
                      onboarding_status
                      update_profile
                    ]

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
            message: result.new_record ? "User created successfully" : "User already exists",
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
      # PATCH/PUT /api/v1/users/:id/heartbeat
      # =========================================================
      def heartbeat
        @user =
          User.find_by(auth0_id: params[:id]) ||
          (User.find(params[:id]) if BSON::ObjectId.legal?(params[:id]))

        unless @user
          return render json: { error: "User not found" }, status: :not_found
        end

        @user.touch(:last_seen_at)

        render json: {
          status:       "ok",
          last_seen_at: @user.last_seen_at
        }, status: :ok
      rescue Mongoid::Errors::DocumentNotFound
        render json: { error: "User not found" }, status: :not_found
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
            payload           = status.to_api_hash
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
      #   2. auth0_id param that is a BSON ObjectId  (deprecated frontend calls)
      #   3. params[:id] as a BSON ObjectId fallback
      def load_user_by_auth0!
        raw = extract_auth0_id

        @user =
          if raw.present?
            found = User.where(auth0_id: raw).first

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

        @user = User.where(auth0_id: id_param).first

        if @user.nil? && bson_object_id?(id_param)
          begin
            @user = User.find(id_param)
          rescue Mongoid::Errors::DocumentNotFound,
                 BSON::ObjectId::Invalid
            @user = nil
          end
        end

        render_error(["User not found"], status: :not_found) unless @user
      end

      # =======================================================
      # SCHOOLS
      # =======================================================

      # Shared implementation used by both #schools and #schools_by_path.
      #
      # Looks up every School whose _id appears in user.school_ids,
      # serializes each one, and renders a success response.
      # Pass deprecated_url: to append the _deprecated migration hint.
      def fetch_schools_for(user, deprecated_url: nil)
        raw_ids = Array(user.try(:school_ids)).map do |id|
          BSON::ObjectId.from_string(id.to_s)
        rescue BSON::Error::InvalidObjectId
          nil
        end.compact

        schools = raw_ids.any? ? School.in(id: raw_ids) : School.none

        data = {
          schools: schools.map { |s| serialize_school(s) }
        }

        data[:_deprecated] = deprecated_payload(deprecated_url) if deprecated_url.present?

        render_success(
          message: "Schools retrieved successfully",
          data:    data
        )
      end

      def serialize_school(school)
        {
          id:         school.id.to_s,
          name:       school.try(:name),
          email:      school.try(:email),
          phone:      school.try(:phone),
          address:    school.try(:address),
          created_at: school.created_at,
          updated_at: school.updated_at
        }.compact
      end

      # =======================================================
      # HELPERS
      # =======================================================

      def extract_auth0_id
        params[:auth0_id] ||
          params.dig(:user, :auth0_id)
      end

      def extract_auth0_id_from_token
        # Extend when JWT-based auth0_id extraction is needed
        nil
      end

      # Returns true when the string is a valid 24-char hex MongoDB ObjectId.
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
          phone:        user.try(:phone),
          phone_number: user.try(:phone_number),
          avatar_url:   user.try(:avatar_url),
          bio:          user.try(:bio),
          timezone:     user.try(:timezone),
          locale:       user.try(:locale),
          roles:        user.try(:roles),
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
        Rails.logger.warn "⚠️  [Users] #{action}: #{data.inspect}"
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