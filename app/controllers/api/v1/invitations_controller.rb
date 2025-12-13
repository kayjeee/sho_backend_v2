# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  def verify_with_details
    token = params[:token]
    invitation = Invitation.find_by(token: token)

    if invitation
      render json: {
        success: true,
        invitation: {
          id: invitation.id.to_s,
          recipient_phone_number: invitation.recipient_phone_number,
          school_id: invitation.school_id.to_s,
          learner_ids: invitation.learner_ids,
          parent_name: invitation.parent_name
        }
      }
    else
      render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found
    end
  end

  def create
    Rails.logger.info "🔹 [InvitationsController] Creating invitation with params: #{params}"
    
    learner_ids = params[:learner_ids] || []
    invitation_service = UserServices::InvitationService.new(
      sender: current_user,
      recipient_phone_number: params[:phone_number],
      school_id: params[:school_id],
      role: params[:role] || 'parent',
      learner_ids: learner_ids,
      parent_name: params[:parent_name],
      grade_id: params[:grade_id]
    )
    
    invitation = invitation_service.call

    if invitation.persisted?
      Rails.logger.info "✅ [InvitationsController] Invitation created successfully: #{invitation.id}"
      render json: { 
        success: true, 
        message: 'Invitation sent successfully.',
        invitation: {
          id: invitation.id.to_s,
          token: invitation.token, # 🔥 CRITICAL: Return the token
          recipient_phone_number: invitation.recipient_phone_number,
          role: invitation.role,
          status: invitation.status
        }
      }, status: :created
    else
      Rails.logger.error "❌ [InvitationsController] Failed to create invitation: #{invitation.errors.full_messages}"
      render json: { 
        success: false, 
        errors: invitation.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  def verify
    token = params[:token]
    invitation = Invitation.find_by(token: token)

    if invitation
      if invitation.update(status: 'verified')
        render json: {
          success: true,
          message: 'Invitation verified successfully.',
          invitation: {
            id: invitation.id.to_s,
            recipient_phone_number: invitation.recipient_phone_number,
            role: invitation.role,
            status: invitation.status,
            learner_ids: invitation.learner_ids,
            learner_names: invitation.learner_names,
            parent_name: invitation.parent_name,
            grade_id: invitation.grade_id,
            school_id: invitation.school_id.to_s
          }
        }, status: :ok
      else
        render json: { success: false, errors: invitation.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found
    end
  end

  private

  def current_user
    @current_user ||= if params[:user_email]
      User.find_by(email: params[:user_email])
    elsif request.headers['X-User-Email']
      User.find_by(email: request.headers['X-User-Email'])
    end
  end
end