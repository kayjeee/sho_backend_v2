# app/controllers/api/v1/schools_controller.rb
module Api
  module V1
    class SchoolsController < ApplicationController
      before_action :set_school, only: [:show, :update, :destroy, :admins, :teachers, :parents]

      # GET /api/v1/schools
      def index
        schools = School.all
        render json: { success: true, schools: schools }, status: :ok
      end

      # GET /api/v1/schools/:school_id/parents/:parent_id
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

      # GET /api/v1/schools/:id/admins
      def admins
        users = fetch_users_by_role('Admin')
        render json: { success: true, data: users }, status: :ok
      end

      # GET /api/v1/schools/:id/teachers
      def teachers
        users = fetch_users_by_role('Teacher')
        render json: { success: true, data: users }, status: :ok
      end

      # GET /api/v1/schools/:id/parents
      def parents
        users = fetch_users_by_role('Parent')
        render json: { success: true, data: users }, status: :ok
      end

      # GET /api/v1/schools/search
      def search
        query = params[:query]

        if query.blank?
          return render json: { success: false, message: "Query parameter is missing." }, status: :bad_request
        end

        school_exists = School.where(schoolName: /^#{Regexp.escape(query)}$/i).exists?
        render json: {
          success: true,
          isAvailable: !school_exists,
          message: school_exists ? "School name is taken" : "School name available"
        }, status: :ok
      rescue => e
        Rails.logger.error "❌ Search error: #{e.message}"
        render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
      end

      # POST /api/v1/schools
      def create
        school_params = params.require(:school).permit(
          :schoolName, :logo, :schoolEmail, :line1, :line2, :country,
          :province, :city, :postalCode, :theme, :latitude, :longitude,
          :website, :facebook, :tiktok, :linkedin,
          :user_id, :user_email, :school_created_by,
          :status
        )

        if School.where(schoolName: school_params[:schoolName]).exists?
          return render json: { success: false, error: "School name already exists" }, status: :unprocessable_entity
        end

        @school = School.new(school_params)
        @school.cash_account ||= 0.0
        @school.payment_history ||= []

        if @school.save
          if school_params[:user_id].present?
            user = find_or_create_user(school_params)

            if user
              promote_user_to_admin(user)   # ✅ Make sure user is Admin
              link_user_to_school(user, @school)
            else
              Rails.logger.error "⚠️ School created but user could not be created/linked"
            end
          end

          render json: { success: true, data: { school: @school } }, status: :created
        else
          render json: { success: false, errors: @school.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Mongo::Error::OperationFailure => e
        render json: { success: false, error: "Database operation failed", details: e.message }, status: :internal_server_error
      end

      # GET /api/v1/schools/:id
      def show
        render json: { success: true, school: @school }, status: :ok
      end

      # PATCH/PUT /api/v1/schools/:id
      def update
        @school.assign_attributes(school_params)
        populate_null_fields(@school)

        if @school.save
          render json: { success: true, school: @school, message: "School updated successfully" }, status: :ok
        else
          render json: { success: false, errors: @school.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/schools/:id
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
            id: user.id.to_s,
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
          :theme, :website, :logo, :status,
          schoolAddress: [:line1, :line2, :country, :province, :city, :postalCode]
        )
      end

      def populate_null_fields(school)
        payload = params[:school] || {}
        %i[country city province latitude longitude facebook linkedin tiktok theme website logo].each do |field|
          school[field] ||= payload[field]
        end
      end

      # 🔑 Create or fetch user if missing
      def find_or_create_user(school_params)
        user = User.find_by(auth0_id: school_params[:user_id])
        return user if user.present?

        result = UserServices::CreateUserService.new(
          user_params: {
            auth0_id: school_params[:user_id],
            email: school_params[:user_email] || "unknown-#{SecureRandom.hex(4)}@demo.com",
            name: school_params[:school_created_by] || "New Admin"
          }
        ).call

        result.success? ? result.user : nil
      end

      # 🔑 Promote user to Admin role
      def promote_user_to_admin(user)
        unless user.roles.include?("admin")
          user.update(roles: ["admin"])
        end
      end

      # 🔑 Ensure user is linked to school + assigned Admin role
      def link_user_to_school(user, school)
        user.add_school(school.id)

        unless UserSchoolRole.where(user_id: user.id, school_id: school.id, role: "Admin").exists?
          UserSchoolRole.create!(user_id: user.id, school_id: school.id, role: "Admin")
        end
      end
    end
  end
end
