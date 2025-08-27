# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    Result = Struct.new(:success?, :user, :errors, :message, keyword_init: true)

    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      user = User.new(@user_params)

      if user.save
        Rails.logger.info "✅ User #{user.auth0_id} created successfully"
        Result.new(success?: true, user: user, message: "User created successfully.")
      else
        Rails.logger.error "❌ Failed to create user: #{user.errors.full_messages.join(', ')}"
        Result.new(success?: false, errors: user.errors.full_messages, message: "User creation failed.")
      end
    rescue StandardError => e
      Rails.logger.error "🔥 Unexpected error in CreateUserService: #{e.message}"
      Result.new(success?: false, errors: [e.message], message: "Unexpected error occurred")
    end
  end
end
