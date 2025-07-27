# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService < ApplicationService
    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      Rails.logger.debug "📥 UserServices::CreateUserService: Creating user with params: #{@user_params.inspect}"
      
      user = User.new(@user_params)
      
      if user.save
        Rails.logger.info "✅ UserServices::CreateUserService: User created successfully - ID: #{user.id}"
        success(user: user)
      else
        Rails.logger.error "❌ UserServices::CreateUserService: Failed to create user. Errors: #{user.errors.full_messages.join(', ')}"
        failure(errors: user.errors.full_messages)
      end
    end
  end
end