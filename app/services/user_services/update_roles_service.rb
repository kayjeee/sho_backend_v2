# app/services/user_services/update_roles_service.rb
module UserServices
  class UpdateRolesService < ::ApplicationService
    def initialize(user:, new_roles:)
      @user = user
      @new_roles = new_roles || []
    end

    def call
      Rails.logger.debug "🛠️ UserServices::UpdateRolesService: Adding roles #{@new_roles.inspect} to user #{@user.auth0_id}"
      
      begin
        @user.roles = (@user.roles + @new_roles).uniq
        
        if @user.save
          Rails.logger.info "✅ UserServices::UpdateRolesService: Roles updated for user #{@user.auth0_id}"
          success(data: { user: @user }, message: "Roles updated successfully")
        else
          Rails.logger.error "❌ UserServices::UpdateRolesService: Failed to update roles. Errors: #{@user.errors.full_messages.join(', ')}"
          failure(errors: @user.errors.full_messages, message: "Failed to update roles")
        end
      rescue StandardError => e
        Rails.logger.error "🔥 UserServices::UpdateRolesService: Unexpected error - #{e.message}"
        failure(errors: [e.message], message: "Unexpected error occurred")
      end
    end
  end
end