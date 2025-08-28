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
      end

      # =========================
      # GET /api/v1/schools/:id/admins
      # =========================
      def admins
        users = fetch_users_by_role('Admin')
        render json: { success: true, data: users }, status: :ok
      end

      # =========================
      # GET /api/v1/schools/:id/teachers
      # =========================
      def teachers
        users = fetch_users_by_role('Teacher')
        render json: { success: true, data: users }, status: :ok
      end

      # =========================
      # GET /api/v1/schools/:id/parents
      # =========================
      def parents
        users = fetch_users_by_role('Parent')
        render json: { success: true, data: users }, status: :ok
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
        render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
      end

      # =========================
      # POST /api/v1/schools
      # =========================
      def create
        @school = School.new(school_params.except(:adminUsers, :theme))

        # Set default values
        @school.cash_account ||= 0.0
        @school.payment_history ||= []
        @school.status ||= "active"

        # Handle theme
        if params[:school][:theme].is_a?(Hash)
          @school.theme = params[:school][:theme][:mode] || params[:school][:theme]["mode"]
        elsif params[:school][:theme].present?
          @school.theme = params[:school][:theme]
        end

        # Handle adminUsers
        if params[:school][:adminUsers].present?
          @school.adminUsers = params[:school][:adminUsers].map do |admin|
            {
              id: admin[:id] || BSON::ObjectId.new.to_s,
              name: admin[:name],
              email: admin[:email],
              role: admin[:role] || "Admin",
              addedAt: admin[:addedAt] || Time.current
            }
          end
        end

        if @school.save
          # Associate user with school if user_id provided
          if school_params[:user_id]
            user = User.find_by(auth0_id: school_params[:user_id])
            user&.add_school(@school.id)
          end

          render json: { success: true, data: { school: @school } }, status: :created
        else
          render json: { success: false, errors: @school.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Mongo::Error::OperationFailure => e
        render json: { success: false, error: "Database operation failed", details: e.message }, status: :internal_server_error
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
        if params[:school] && params[:school][:theme].is_a?(Hash)
          @school.theme = params[:school][:theme][:mode] || params[:school][:theme]["mode"]
        elsif params[:school] && params[:school][:theme].present?
          @school.theme = params[:school][:theme]
        end

        # Handle adminUsers
        if params[:school] && params[:school][:adminUsers].present?
          @school.adminUsers = params[:school][:adminUsers].map do |admin|
            {
              id: admin[:id] || BSON::ObjectId.new.to_s,
              name: admin[:name],
              email: admin[:email],
              role: admin[:role] || "Admin",
              addedAt: admin[:addedAt] || Time.current
            }
          end
        end

        if @school.update(school_params.except(:theme, :adminUsers))
          render json: { success: true, school: @school, message: "School updated successfully" }, status: :ok
        else
          render json: { success: false, errors: @school.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # =========================
      # DELETE /api/v1/schools/:id
      # =========================
      def destroy
        @school.destroy
        render json: { success: true, message: "School deleted successfully" }, status: :ok
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
            id: user.id,
            name: user.name,
            email: user.email,
            auth0_id: user.auth0_id,
            role: role
          }
        end
      end

      def school_params
        params.require(:school).permit(
          :schoolName, :schoolEmail, :country, :city, :province,
          :latitude, :longitude, :facebook, :linkedin, :tiktok,
          :website, :logo, :status, :line1, :line2, :postalCode,
          :user_id, :user_email, :school_created_by, :theme,
          adminUsers: [:id, :name, :email, :role, :addedAt]
        )
      end
    end
  end
end
