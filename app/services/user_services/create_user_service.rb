# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    Result = Struct.new(:success?, :user, :errors, keyword_init: true)

    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      # 🔑 Check if user already exists → return it
      user = User.find_or_initialize_by(auth0_id: @user_params[:auth0_id])
      user.assign_attributes(@user_params)

      if user.save
        Result.new(success?: true, user: user, errors: [])
      else
        Result.new(success?: false, user: nil, errors: user.errors.full_messages)
      end
    end
  end
end
