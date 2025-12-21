# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  include Secured
  before_action :authorize, only: [:create, :verify]

  def verify_with_details
    token = params[:token]
    invitation = Invitation.find_by(token: token, status: 'pending')

    if invitation
      render json: { success: true, invitation: { id: invitation.id.to_s, recipient_phone_number: invitation.recipient_phone_number, school_id: invitation.school_id.to_s, learner_number: invitation.learner_number, parent_name: invitation.parent_name } }
    else
      render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found
    end
  end

  def create
    current_user_auth0_id = @decoded_token.token['sub']
    sender = User.find_by(auth0_id: current_user_auth0_id)

    invitation_service = UserServices::InvitationService.new(
      sender: sender, recipient_phone_number: params[:phone_number], school_id: params[:school_id],
      learner_number: params[:learner_number], role: params[:role] || 'parent', parent_name: params[:parent_name], grade_id: params[:grade_id]
    )
    
    invitation = invitation_service.call

    if invitation.persisted?
      render json: { success: true, message: 'Invitation sent successfully.', invitation: { id: invitation.id.to_s, token: invitation.token, recipient_phone_number: invitation.recipient_phone_number, role: invitation.role, status: invitation.status } }, status: :created
    else
      render json: { success: false, errors: invitation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def verify
    token = params[:token]
    invitation = Invitation.find_by(token: token, status: 'pending')

    return render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found unless invitation

    learner = Learner.find_by(school_id: invitation.school_id, accession_number: invitation.learner_number)

    return render json: { success: false, message: 'Learner not found for this invitation.' }, status: :not_found unless learner

    current_user_auth0_id = @decoded_token.token['sub']

    # Correct Logic: Add the user's ID to the `parent_auth0_ids` array.
    if learner.add_to_set(parent_auth0_ids: current_user_auth0_id)
      invitation.update(status: 'verified')
      render json: { success: true, message: 'User linked to learner successfully.' }, status: :ok
    else
      render json: { success: false, error: 'Failed to link learner', details: learner.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
