module Api
    module V1
      class AdminUsersController < ApplicationController
        before_action :set_school, only: [:create]
  
        def create
          admin_user = @school.admin_users.new(admin_user_params)
          admin_user.invited_by = request.remote_ip
          admin_user.date_invited = Time.current
  
          if admin_user.save
            render json: { message: 'Admin user created successfully', admin_user: admin_user }, status: :created
          else
            render json: { error: admin_user.errors.full_messages }, status: :unprocessable_entity
          end
        end
  
        def schools_for_admin
          user_email = params[:email]
          user_role = "Admin"
  
          # Find all admin_users where the email matches and the role is Admin
          admin_users = AdminUser.where(admin_user_email: user_email, admin_user_roles: user_role)
  
          # Extract school_ids from the admin_users
          school_ids = admin_users.pluck(:school_id)
  
          # Find all schools with the extracted school_ids
          schools = School.where(:_id.in => school_ids)
  
          if schools.any?
            render json: { schools: schools }, status: :ok
          else
            render json: { message: 'No schools found where the user is an admin' }, status: :not_found
          end
        end
  
        private
  
        def set_school
          @school = School.find_by(id: params[:school_id])
          return render json: { error: 'School not found' }, status: :not_found unless @school
        end
  
        def admin_user_params
          params.permit(:admin_user_email, :admin_user_schoolname, admin_user_roles: [])
        end
      end
    end
  end