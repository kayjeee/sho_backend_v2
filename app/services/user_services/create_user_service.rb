# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    Result = Struct.new(:success?, :user, :errors, keyword_init: true)

    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      user = User.find_or_initialize_by(auth0_id: @user_params[:auth0_id])
      user.assign_attributes(@user_params.except(:invitation_token))

      invitation_token = @user_params[:invitation_token]
      invitation = nil

      if invitation_token
        invitation = Invitation.find_by(token: invitation_token, :status.in => ['pending', 'verified'])
        if invitation
          user.phone_number ||= invitation.recipient_phone_number
          user.roles << 'parent' unless user.roles.include?('parent')
          user.schools << invitation.school unless user.schools.include?(invitation.school)
        end
      end

      if user.save
        if invitation&.persisted?
          invitation.update(status: 'accepted')

          ParentLinkageService.new(
            user: user,
            learner_ids: invitation.learner_ids
          ).call
        end
        Result.new(success?: true, user: user, errors: [])
      else
        Result.new(success?: false, user: nil, errors: user.errors.full_messages)
      end
    end
  end
end
