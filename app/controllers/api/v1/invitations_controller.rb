# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  # 🚫 Removed before_action :authenticate_admin!

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

  # ✅ Still resolves user from X-User-Email header or param
  def current_user
    @current_user ||= if params[:user_email]
                        User.find_by(email: params[:user_email])
                      elsif request.headers['X-User-Email']
                        User.find_by(email: request.headers['X-User-Email'])
                      end
  end
end