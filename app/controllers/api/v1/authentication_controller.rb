# app/controllers/api/v1/authentication_controller.rb
class Api::V1::AuthenticationController < ApplicationController
  def login
    token = params[:access_token]
    validation_response = Auth0Client.validate_token(token)

    if validation_response.success?
      decoded_token = validation_response.decoded_token
      auth0_id = decoded_token[0]['sub']

      user = User.find_or_create_by(auth0_id: auth0_id) do |u|
        u.email = decoded_token[0]['email']
        u.name = decoded_token[0]['name']
      end

      if session[:invitation_token].present?
        invitation = Invitation.find_by(token: session[:invitation_token])

        if invitation
          user.phone_number ||= invitation.recipient_phone_number
          user.school_ids << invitation.school_id unless user.school_ids.include?(invitation.school_id)
          user.save!

          invitation.update!(status: 'used', user_id: user.id)
          session.delete(:invitation_token)
        end
      end

      render json: { success: true, user: user.to_api_hash }
    else
      render json: { success: false, error: validation_response.error.message }, status: :unauthorized
    end
  end
end
