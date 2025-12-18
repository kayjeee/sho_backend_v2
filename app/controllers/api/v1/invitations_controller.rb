# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

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
    Rails.logger.info "🔹 [InvitationsController] Creating learner-centric invitation with params: #{params}"
    
    invitation_service = UserServices::InvitationService.new(
      sender: current_user,
      recipient_phone_number: params[:phone_number],
      school_id: params[:school_id],
      learner_number: params[:learner_number],
      role: params[:role] || 'parent',
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
          token: invitation.token,
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
    invitation = Invitation.find_by(token: token, status: 'pending')

    unless invitation
      render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found and return
    end

    learner = Learner.find_by(school_id: invitation.school_id, accession_number: invitation.learner_number)

    unless learner
      render json: { success: false, message: 'Learner not found for this invitation.' }, status: :not_found and return
    end

    # Link the learner to the current user
    if current_user && !current_user.learner_ids.include?(learner.id.to_s)
      current_user.learner_ids << learner.id.to_s
      current_user.save
    end

    invitation.update(status: 'verified')

    render json: {
      success: true,
      message: 'User linked to learner successfully.',
      user: { auth0_id: current_user&.auth0_id },
      learner: { learner_number: learner.accession_number, school_id: learner.school_id.to_s },
      linked: true
    }, status: :ok
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
