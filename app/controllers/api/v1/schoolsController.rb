module Api
  module V1
    class SchoolsController < ApplicationController
      before_action :set_school, only: [:show, :update, :destroy, :admins, :teachers, :parents]

      # =========================
      # GET /api/v1/schools
      # =========================
      def index
        schools = School.all
        render json: { success: true, schools: schools }, status: :ok
      rescue => e
        Rails.logger.error "Schools index failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Failed to fetch schools", details: e.message }, status: :internal_server_error
      end

      # =========================
      # GET /api/v1/schools/:school_id/parents/:parent_id
      # =========================
      def show_parent
        user_role = UserSchoolRole.find_by(
          school_id: params[:id],
          user_id: params[:parent_id],
          role: 'Parent'
        )

        unless user_role
          return render json: { success: false, message: "Parent not found in this school" }, status: :not_found
        end

        parent = User.find(params[:parent_id])
        render json: {
          success: true,
          parent: {
            id: parent.id.to_s,
            name: parent.name,
            email: parent.email,
            auth0_id: parent.auth0_id,
            role: 'Parent'
          }
        }, status: :ok
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: "Parent not found" }, status: :not_found
      rescue => e
        Rails.logger.error "Show parent failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Failed to fetch parent", details: e.message }, status: :internal_server_error
      end

      # =========================
      # GET /api/v1/schools/:id/admins
      # =========================
      def admins
        users = fetch_users_by_role('Admin')
        render json: { success: true, data: users }, status: :ok
      rescue => e
        Rails.logger.error "Fetch admins failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Failed to fetch admins", details: e.message }, status: :internal_server_error
      end

      # =========================
      # GET /api/v1/schools/:id/teachers
      # =========================
      def teachers
        users = fetch_users_by_role('Teacher')
        render json: { success: true, data: users }, status: :ok
      rescue => e
        Rails.logger.error "Fetch teachers failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Failed to fetch teachers", details: e.message }, status: :internal_server_error
      end

      # =========================
      # GET /api/v1/schools/:id/parents
      # =========================
      def parents
        users = fetch_users_by_role('Parent')
        render json: { success: true, data: users }, status: :ok
      rescue => e
        Rails.logger.error "Fetch parents failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Failed to fetch parents", details: e.message }, status: :internal_server_error
      end

      # =========================
      # GET /api/v1/schools/search?query=Name
      # =========================
      def search
        query = params[:query]
        return render json: { success: false, message: "Query parameter is missing." }, status: :bad_request if query.blank?

        school_exists = School.where(schoolName: /^#{Regexp.escape(query)}$/i).exists?
        render json: {
          success: true,
          isAvailable: !school_exists,
          message: school_exists ? "School name is taken" : "School name available"
        }, status: :ok
      rescue => e
        Rails.logger.error "School search failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
      end

      # =========================
      # POST /api/v1/schools
      # =========================
      def create
        # Extract permitted params (excluding nested attributes we'll handle separately)
        permitted_params = school_params.except(:adminUsers, :theme, :invites, :user_id, :user_email, :status)
        @school = School.new(permitted_params)

        # Set default values only if the field exists in the model
        set_default_values

        # Handle theme safely
        handle_theme_assignment

        # Handle adminUsers safely
        handle_admin_users_assignment

        # Handle invites safely
        handle_invites_assignment

        if @school.save
          # Associate user with school if user_id provided
          associate_user_with_school

          render json: { success: true, data: { school: @school } }, status: :created
        else
          Rails.logger.warn "School validation failed: #{@school.errors.full_messages.join(', ')}"
          render json: { success: false, errors: @school.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Mongo::Error::OperationFailure => e
        Rails.logger.error "MongoDB operation failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Database operation failed", details: e.message }, status: :internal_server_error
      rescue ActionController::ParameterMissing => e
        Rails.logger.warn "Missing required parameter: #{e.message}"
        render json: { success: false, error: "Missing required parameter", details: e.message }, status: :bad_request
      rescue => e
        Rails.logger.error "School creation failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "An unexpected error occurred", details: e.message }, status: :internal_server_error
      end

      # =========================
      # GET /api/v1/schools/:id
      # =========================
      def show
        render json: { success: true, school: @school }, status: :ok
      end

      # =========================
      # PATCH/PUT /api/v1/schools/:id
      # =========================
      def update
        # Handle theme
        handle_theme_assignment

        # Handle adminUsers
        handle_admin_users_assignment

        # Handle invites
        handle_invites_assignment

        # Update with permitted params (excluding those handled above)
        permitted_params = school_params.except(:theme, :adminUsers, :invites, :user_id, :user_email, :status)
        
        # Handle status separately if it exists in the model
        if @school.respond_to?(:status=) && params[:school] && params[:school][:status].present?
          @school.status = params[:school][:status]
        end

        if @school.update(permitted_params)
          render json: { success: true, school: @school, message: "School updated successfully" }, status: :ok
        else
          Rails.logger.warn "School update validation failed: #{@school.errors.full_messages.join(', ')}"
          render json: { success: false, errors: @school.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Mongo::Error::OperationFailure => e
        Rails.logger.error "MongoDB operation failed during update: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Database operation failed", details: e.message }, status: :internal_server_error
      rescue => e
        Rails.logger.error "School update failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "An unexpected error occurred", details: e.message }, status: :internal_server_error
      end

      # =========================
      # DELETE /api/v1/schools/:id
      # =========================
      def destroy
        @school.destroy
        render json: { success: true, message: "School deleted successfully" }, status: :ok
      rescue => e
        Rails.logger.error "School deletion failed: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { success: false, error: "Failed to delete school", details: e.message }, status: :internal_server_error
      end

      private

      def set_school
        @school = School.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: "School not found" }, status: :not_found
      rescue BSON::ObjectId::Invalid => e
        render json: { success: false, message: "Invalid school ID: #{e.message}" }, status: :bad_request
      end

      def fetch_users_by_role(role)
        user_roles = UserSchoolRole.where(school_id: @school.id, role: role)
        User.in(id: user_roles.pluck(:user_id)).map do |user|
          {
            id: user.id.to_s,
            name: user.name,
            email: user.email,
            auth0_id: user.auth0_id,
            role: role
          }
        end
      end

      # Set default values only if fields exist in the model
      def set_default_values
        # Only set values if the model has these attributes
        @school.cash_account = 0.0 if @school.respond_to?(:cash_account=)
        @school.payment_history = [] if @school.respond_to?(:payment_history=)
        
        # Handle status carefully - only set if the field exists
        if @school.respond_to?(:status=)
          @school.status = params.dig(:school, :status) || "active"
        end
      end

      # Handle theme assignment with safety checks
      def handle_theme_assignment
        return unless params[:school] && params[:school][:theme].present?

        theme_value = params[:school][:theme]
        
        if theme_value.is_a?(Hash)
          # Try symbol key first, then string key
          @school.theme = theme_value[:mode] || theme_value["mode"] || theme_value.to_s
        else
          @school.theme = theme_value.to_s
        end
      rescue => e
        Rails.logger.warn "Failed to set theme: #{e.message}"
        # Continue without setting theme
      end

      # Handle adminUsers assignment with safety checks
      def handle_admin_users_assignment
        return unless params[:school] && params[:school][:adminUsers].present?
        return unless params[:school][:adminUsers].is_a?(Array)

        @school.adminUsers = params[:school][:adminUsers].map do |admin|
          # Support both symbol and string keys
          {
            id: admin[:id] || admin["id"] || BSON::ObjectId.new.to_s,
            name: admin[:name] || admin["name"],
            email: admin[:email] || admin["email"],
            role: admin[:role] || admin["role"] || "Admin",
            addedAt: admin[:addedAt] || admin["addedAt"] || Time.current
          }
        end.compact
      rescue => e
        Rails.logger.warn "Failed to set adminUsers: #{e.message}"
        @school.adminUsers = []
      end

      # Handle invites assignment with safety checks
      def handle_invites_assignment
        return unless params[:school] && params[:school][:invites].present?
        return unless params[:school][:invites].is_a?(Array)

        @school.invites = params[:school][:invites].map do |invite|
          # Support both symbol and string keys
          {
            id: invite[:id] || invite["id"] || BSON::ObjectId.new.to_s,
            email: invite[:email] || invite["email"],
            role: invite[:role] || invite["role"] || "Staff",
            status: invite[:status] || invite["status"] || "pending",
            invitedAt: invite[:invitedAt] || invite["invitedAt"] || Time.current
          }
        end.compact
      rescue => e
        Rails.logger.warn "Failed to set invites: #{e.message}"
        @school.invites = []
      end

      # Associate user with school after creation
      def associate_user_with_school
        user_id = school_params[:user_id]
        return unless user_id.present?

        user = User.find_by(auth0_id: user_id)
        
        if user
          begin
            user.add_school(@school.id)
            Rails.logger.info "Successfully associated user #{user_id} with school #{@school.id}"
          rescue => e
            Rails.logger.error "Failed to associate user with school: #{e.message}"
            # Don't fail the request - school was created successfully
          end
        else
          Rails.logger.warn "User not found with auth0_id: #{user_id}"
          # Don't fail the request - school was created successfully
        end
      end

      def school_params
        params.require(:school).permit(
          :schoolName, :schoolEmail, :country, :city, :province,
          :latitude, :longitude, :facebook, :linkedin, :tiktok,
          :website, :logo, :status, :line1, :line2, :postalCode,
          :user_id, :user_email, :school_created_by, :theme,
          adminUsers: [:id, :name, :email, :role, :addedAt],
          invites: [:id, :email, :role, :status, :invitedAt]
        )
      end
    end
  end
end