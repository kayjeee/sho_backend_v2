# app/services/user_services/update_roles_service.rb
module UserServices
  class UpdateRolesService < ApplicationService
    def initialize(user:, new_roles:)
      @user = user
      @new_roles = new_roles || []
    end

    def call
      Rails.logger.debug "🛠️ UserServices::UpdateRolesService: Adding roles #{@new_roles.inspect} to user #{@user.auth0_id}"
      
      @user.roles = (@user.roles + @new_roles).uniq
      
      if @user.save
        Rails.logger.info "✅ UserServices::UpdateRolesService: Roles updated for user #{@user.auth0_id}"
        success(user: @user)
      else
        Rails.logger.error "❌ UserServices::UpdateRolesService: Failed to update roles. Errors: #{@user.errors.full_messages.join(', ')}"
        failure(errors: @user.errors.full_messages)
      end
    end
  end
end