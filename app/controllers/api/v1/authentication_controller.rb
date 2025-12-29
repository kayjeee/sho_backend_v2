# app/controllers/api/v1/authentication_controller.rb
class Api::V1::AuthenticationController < ApplicationController
  def login
    token = params[:access_token]
    validation_response = Auth0Client.validate_token(token)

    unless validation_response.success?
      return render json: { success: false, error: validation_response.error.message }, status: :unauthorized
    end

    decoded_token = validation_response.decoded_token[0]
    auth0_id = decoded_token['sub']
    email = decoded_token['email']
    name = decoded_token['name']

    user = find_or_initialize_user(auth0_id, email)
    was_new_record = user.new_record?

    user.name ||= name
    user.email ||= email

    invitation = find_invitation
    if invitation
      user.roles << (invitation.role || 'parent')
      user.phone_number ||= invitation.recipient_phone_number
      user.school_ids << invitation.school_id unless user.school_ids.include?(invitation.school_id)
    end

    user.roles << 'parent' if user.roles.empty?

    if user.save
      user.initialize_onboarding_status if was_new_record
      if invitation
        invitation.update!(status: 'used', user_id: user.id)
        session.delete(:invitation_token)
      end
      render json: { success: true, user: user.to_api_hash }
    else
      render json: { success: false, errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def find_or_initialize_user(auth0_id, email)
    user = User.find_by(auth0_id: auth0_id)
    return user if user

    user = User.find_by(email: email)
    if user
      user.auth0_id = auth0_id
      return user
    end

    User.new(auth0_id: auth0_id, email: email)
  end

  def find_invitation
    return nil unless session[:invitation_token].present?
    Invitation.find_by(token: session[:invitation_token])
  end
end
