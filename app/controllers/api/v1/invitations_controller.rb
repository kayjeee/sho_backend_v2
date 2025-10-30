# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  before_action :authenticate_admin!

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

  private

  def authenticate_admin!
    unless current_user&.has_role?('admin')
      render json: { success: false, error: 'You are not authorized to perform this action.' }, status: :unauthorized
      return
    end
  end

  def current_user
    # Find user by email from params or headers (without authentication)
    @current_user ||= if params[:user_email]
                        User.find_by(email: params[:user_email])
                      elsif request.headers['X-User-Email']
                        User.find_by(email: request.headers['X-User-Email'])
                      end
  end
end