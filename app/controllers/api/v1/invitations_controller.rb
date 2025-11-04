# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  include Secured

  def create
    invitation_service = UserServices::InvitationService.new(
      sender: current_user,
      recipient_phone_number: params[:phone_number],
      school_id: params[:school_id]
    )
    invitation = invitation_service.call

    if invitation.persisted?
      render json: { success: true, message: 'Invitation sent successfully.' }, status: :created
    else
      render json: { success: false, errors: invitation.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
