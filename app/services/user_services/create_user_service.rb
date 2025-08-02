# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService 
    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      user = User.new(@user_params)
      if user.save
        success(user: user)
      else
        failure(errors: user.errors.full_messages)
      end
    end
  end
end
