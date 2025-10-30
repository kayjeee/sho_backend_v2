# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    Result = Struct.new(:success?, :user, :errors, keyword_init: true)

    def initialize(user_params:, invitation_token: nil)
      @user_params = user_params
      @invitation_token = invitation_token
    end

    def call
      user = User.find_or_initialize_by(auth0_id: @user_params[:auth0_id])
      user.assign_attributes(@user_params)

      if @invitation_token
        invitation = Invitation.find_by(token: @invitation_token, status: 'pending')
        if invitation
          user.roles << 'parent'
          user.schools << invitation.school
          invitation.update(status: 'accepted')
        end
      end

      if user.save
        Result.new(success?: true, user: user, errors: [])
      else
        Result.new(success?: false, user: nil, errors: user.errors.full_messages)
      end
    end
  end
end
