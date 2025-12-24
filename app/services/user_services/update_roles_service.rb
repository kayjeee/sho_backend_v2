# app/services/user_services/update_roles_service.rb
module UserServices
  class UpdateRolesService
    Result = Struct.new(:success?, :user, :errors, :message, keyword_init: true)

    def initialize(user:, new_roles:)
      @user = user
      @new_roles = Array(new_roles).map(&:downcase)
    end

    def self.call(user:, new_roles:)
      new(user: user, new_roles: new_roles).call
    end

    def call
      Rails.logger.debug "🛠️ UserServices::UpdateRolesService: Adding roles #{@new_roles.inspect} to user #{@user.auth0_id}"

      @user.roles = (@user.roles + @new_roles).uniq

      if @user.save
        Rails.logger.info "✅ Roles updated for user #{@user.auth0_id}"
        Result.new(success?: true, user: @user, message: "Roles updated successfully")
      else
        Rails.logger.error "❌ Failed to update roles. Errors: #{@user.errors.full_messages.join(', ')}"
        Result.new(success?: false, errors: @user.errors.full_messages, message: "Failed to update roles")
      end

    rescue StandardError => e
      Rails.logger.error "🔥 Unexpected error updating roles: #{e.message}"
      Result.new(success?: false, errors: [e.message], message: "Unexpected error occurred")
    end
  end
end
