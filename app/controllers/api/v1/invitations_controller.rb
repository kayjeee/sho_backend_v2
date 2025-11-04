# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  include Secured

  before_action :validate_params, only: [:create]

  def create
    invitation_service = UserServices::InvitationService.new(
      sender: current_user,
      recipient_phone_number: params[:phone_number],
      school_id: params[:school_id],
      role: params[:role]
    )
    invitation = invitation_service.call

    if invitation.persisted?
      render json: { success: true, message: 'Invitation sent successfully.' }, status: :created
    else
      render json: { success: false, errors: invitation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def validate_params
    required_params = [:phone_number, :school_id, :role]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      render json: { success: false, errors: "Missing parameters: #{missing_params.join(', ')}" }, status: :unprocessable_entity
    end
  end
end
