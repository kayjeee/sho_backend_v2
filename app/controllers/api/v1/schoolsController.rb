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
        # Get all permitted params
        permitted = school_params
        
        # Extract and remove special fields that need custom handling
        theme_data = permitted.delete(:theme)
        admin_users_data = permitted.delete(:adminUsers)
        invites_data = permitted.delete(:invites)
        
        # Create school with basic fields
        @school = School.new(permitted)

        # Set default values
        @school.cash_account ||= 0.0
        @school.payment_history ||= []
        @school.status ||= "active"

        # Handle theme as a Hash (not string)
        if theme_data.present?
          @school.theme = parse_theme(theme_data)
        else
          @school.theme = {}
        end

        # Handle adminUsers
        if admin_users_data.present? && admin_users_data.is_a?(Array)
          @school.adminUsers = admin_users_data.map do |admin|
            {
              id: admin[:id] || admin["id"] || Time.now.to_i.to_s,
              name: admin[:name] || admin["name"],
              email: admin[:email] || admin["email"],
              role: admin[:role] || admin["role"] || "Administrator",
              addedAt: admin[:addedAt] || admin["addedAt"] || Time.current
            }
          end.compact
        else
          @school.adminUsers = []
        end

        # Handle invites
        if invites_data.present? && invites_data.is_a?(Array)
          @school.invites = invites_data.map do |invite|
            {
              id: invite[:id] || invite["id"] || Time.now.to_i.to_s,
              email: invite[:email] || invite["email"],
              role: invite[:role] || invite["role"] || "Staff",
              status: invite[:status] || invite["status"] || "pending",
              invitedAt: invite[:invitedAt] || invite["invitedAt"] || Time.current
            }
          end.compact
        else
          @school.invites = []
        end

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
        # Get all permitted params
        permitted = school_params
        
        # Extract and remove special fields that need custom handling
        theme_data = permitted.delete(:theme)
        admin_users_data = permitted.delete(:adminUsers)
        invites_data = permitted.delete(:invites)

        # Handle theme as a Hash (not string)
        if theme_data.present?
          @school.theme = parse_theme(theme_data)
        end

        # Handle adminUsers
        if admin_users_data.present? && admin_users_data.is_a?(Array)
          @school.adminUsers = admin_users_data.map do |admin|
            {
              id: admin[:id] || admin["id"] || Time.now.to_i.to_s,
              name: admin[:name] || admin["name"],
              email: admin[:email] || admin["email"],
              role: admin[:role] || admin["role"] || "Administrator",
              addedAt: admin[:addedAt] || admin["addedAt"] || Time.current
            }
          end.compact
        end

        # Handle invites
        if invites_data.present? && invites_data.is_a?(Array)
          @school.invites = invites_data.map do |invite|
            {
              id: invite[:id] || invite["id"] || Time.now.to_i.to_s,
              email: invite[:email] || invite["email"],
              role: invite[:role] || invite["role"] || "Staff",
              status: invite[:status] || invite["status"] || "pending",
              invitedAt: invite[:invitedAt] || invite["invitedAt"] || Time.current
            }
          end.compact
        end

        if @school.update(permitted)
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

      # Parse theme data into proper Hash format
      def parse_theme(theme_data)
        return {} if theme_data.blank?
        
        if theme_data.is_a?(Hash)
          # Already a hash, extract mode and value
          {
            "mode" => theme_data[:mode] || theme_data["mode"] || "",
            "value" => theme_data[:value] || theme_data["value"] || ""
          }
        elsif theme_data.is_a?(String)
          # If it's just a string (like "white"), treat it as mode
          { "mode" => theme_data, "value" => "" }
        else
          {}
        end
      rescue => e
        Rails.logger.warn "Failed to parse theme: #{e.message}"
        {}
      end

      # Associate user with school after creation
      def associate_user_with_school
        user_id = @school.user_id
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
          :user_id, :user_email, :school_created_by,
          theme: [:mode, :value],
          adminUsers: [:id, :name, :email, :role, :addedAt],
          invites: [:id, :email, :role, :status, :invitedAt]
        )
      end
    end
  end
end