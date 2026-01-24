# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    Result = Struct.new(:success?, :user, :errors, :new_record?, keyword_init: true)

    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      # First, try to find user by auth0_id (primary identifier)
      user = User.find_by(auth0_id: @user_params[:auth0_id])
      
      # If not found by auth0_id, try by email (secondary identifier)
      user ||= User.find_by(email: @user_params[:email]) if @user_params[:email].present?
      
      if user
        # User exists - update safe attributes only
        safe_attributes = @user_params.except(:email, :auth0_id)
        user.assign_attributes(safe_attributes) if safe_attributes.any?
        
        if user.save
          Result.new(success?: true, user: user, errors: [], new_record?: false)
        else
          Result.new(success?: false, user: nil, errors: user.errors.full_messages, new_record?: false)
        end
      else
        # User doesn't exist - create new one
        user = User.new(@user_params)
        
        if user.save
          Result.new(success?: true, user: user, errors: [], new_record?: true)
        else
          Result.new(success?: false, user: nil, errors: user.errors.full_messages, new_record?: false)
        end
      end
    rescue => e
      Result.new(success?: false, user: nil, errors: [e.message], new_record?: false)
    end
  end
end