module Api
  module V1
    class AdminUsersController < ApplicationController
      before_action :set_school, only: [ :create ]

      def create
        admin_user = @school.admin_users.new(admin_user_params)
        admin_user.invited_by = request.remote_ip
        admin_user.date_invited = Time.current

        if admin_user.save
          render json: { message: "Admin user created successfully", admin_user: admin_user }, status: :created
        else
          render json: { error: admin_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def schools_for_admin
  user_email = params[:email]
  user_role = "Admin"

  if user_email.blank?
    return render json: { error: "Email parameter is required" }, status: :bad_request
  end

  # Find schools from AdminUser records
  admin_user_school_ids = AdminUser.where(
    admin_user_email: user_email,
    :admin_user_roles.in => [ user_role ]
  ).pluck(:school_id)

  # Also include schools where user is creator (fallback if AdminUser not used)
  created_school_ids = School.where(user_email: user_email).pluck(:id)

  # Merge and remove duplicates
  all_school_ids = (admin_user_school_ids + created_school_ids).uniq

  schools = School.where(:_id.in => all_school_ids)

  if schools.any?
    render json: { schools: schools }, status: :ok
  else
    render json: { message: "No schools found where the user is an admin" }, status: :not_found
  end
  end

      private

      def set_school
        @school = School.find_by(id: params[:school_id])
        render json: { error: "School not found" }, status: :not_found unless @school
      end

      def admin_user_params
        params.permit(:admin_user_email, :admin_user_schoolname, admin_user_roles: [])
      end
    end
  end
end
