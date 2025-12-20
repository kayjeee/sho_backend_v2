# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  include Secured
  before_action :authorize, only: [:create, :verify] # Protect create and verify actions

  # GET /invitations/:token/verify_with_details (Does not require auth)
  # This is a public endpoint to let a user see invitation details before signing up.
  def verify_with_details
    token = params[:token]
    invitation = Invitation.find_by(token: token, status: 'pending')

    if invitation
      render json: {
        success: true,
        invitation: {
          id: invitation.id.to_s,
          recipient_phone_number: invitation.recipient_phone_number,
          school_id: invitation.school_id.to_s,
          learner_number: invitation.learner_number, # Use learner_number for consistency
          parent_name: invitation.parent_name
        }
      }
    else
      render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found
    end
  end

  # POST /api/v1/invitations (Requires auth)
  # Creates an invitation. The sender is the authenticated user.
  def create
    current_user_auth0_id = @decoded_token.token['sub']
    sender = User.find_by(auth0_id: current_user_auth0_id)

    Rails.logger.info "🔹 [InvitationsController] Creating learner-centric invitation with params: #{params}"
    
    invitation_service = UserServices::InvitationService.new(
      sender: sender,
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

  # POST /api/v1/invitations/verify (Requires auth)
  # Verifies an invitation token and links the learner to the authenticated user.
  def verify
    token = params[:token]
    invitation = Invitation.find_by(token: token, status: 'pending')

    unless invitation
      return render json: { success: false, message: 'Invalid or expired invitation link.' }, status: :not_found
    end

    learner = Learner.find_by(school_id: invitation.school_id, accession_number: invitation.learner_number)

    unless learner
      return render json: { success: false, message: 'Learner not found for this invitation.' }, status: :not_found
    end

    # Get the authenticated user's ID from the token provided by the `authorize` action
    current_user_auth0_id = @decoded_token.token['sub']

    # Correctly link the learner by adding the user's auth0_id to the learner's parent array
    learner.add_to_set(parent_auth0_ids: current_user_auth0_id)

    invitation.update(status: 'verified')

    render json: {
      success: true,
      message: 'User linked to learner successfully.',
      learner: { learner_number: learner.accession_number, school_id: learner.school_id.to_s },
      linked: true
    }, status: :ok
  end
end
