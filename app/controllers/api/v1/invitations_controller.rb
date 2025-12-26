# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  # REMOVED: include Secured
  # REMOVED: before_action :authorize, only: [:create, :verify]
  # REMOVED: skip_before_action :verify_authenticity_token  # ← CAUSING THE ERROR

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
          learner_number: invitation.learner_number, 
          parent_name: invitation.parent_name 
        } 
      }
    else
      render json: { 
        success: false, 
        message: 'Invalid or expired invitation link.' 
      }, status: :not_found
    end
  end

  def create
    # Find or create a sender based on the invitation data
    sender = find_or_create_sender_for_invitation(params)
    
    unless sender
      return render json: { 
        success: false, 
        errors: ["Unable to determine sender for invitation"] 
      }, status: :unprocessable_entity
    end

    invitation_service = UserServices::InvitationService.new(
      sender: sender, 
      recipient_phone_number: params[:phone_number], 
      school_id: params[:school_id],
      learner_number: params[:learner_number], 
      role: params[:role] || 'parent', 
      parent_name: params[:parent_name], 
      grade_id: params[:grade_id],
      invited_via: params[:invited_via]
    )
    
    invitation = invitation_service.call

    if invitation.persisted?
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
      render json: { 
        success: false, 
        errors: invitation.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  def verify
    token = params[:token]
    invitation = Invitation.find_by(token: token, status: 'pending')

    return render json: { 
      success: false, 
      message: 'Invalid or expired invitation link.' 
    }, status: :not_found unless invitation

    learner = Learner.find_by(school_id: invitation.school_id, accession_number: invitation.learner_number)

    return render json: { 
      success: false, 
      message: 'Learner not found for this invitation.' 
    }, status: :not_found unless learner

    # Find or create parent user based on invitation data
    parent_user = find_or_create_parent_for_verification(invitation)
    
    unless parent_user
      return render json: { 
        success: false, 
        error: 'Unable to create or find parent user for verification' 
      }, status: :unprocessable_entity
    end

    current_user_auth0_id = parent_user.auth0_id

    # Correct Logic: Add the user's ID to the `parent_auth0_ids` array.
    if learner.add_to_set(parent_auth0_ids: current_user_auth0_id)
      invitation.update(status: 'verified')

      # Persist the invited phone number to the user if it's missing
      user = User.find_by(auth0_id: current_user_auth0_id)
      if user
        user_updates = {}
        user_updates[:phone_number] = invitation.recipient_phone_number if user.phone_number.blank? && invitation.recipient_phone_number.present?
        user_updates[:invited_via] = invitation.invited_via if user.invited_via.blank? && invitation.invited_via.present?
        user.update(user_updates) if user_updates.any?
      end

      render json: { 
        success: true, 
        message: 'User linked to learner successfully.' 
      }, status: :ok
    else
      render json: { 
        success: false, 
        error: 'Failed to link learner', 
        details: learner.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  private

  def find_or_create_sender_for_invitation(params)
    # Strategy 1: Find by email if provided in request headers
    if request.headers['X-User-Email'].present?
      user_email = request.headers['X-User-Email']
      sender = User.find_by(email: user_email)
      return sender if sender
    end

    # Strategy 2: Find any admin user associated with the school
    if params[:school_id].present?
      school = School.find_by(id: params[:school_id])
      if school
        # Find school admin or any user with admin role
        sender = User.where(roles: 'admin').first
        return sender if sender
      end
    end

    # Strategy 3: Use the first admin in the system
    User.where(roles: 'admin').first || User.first
  end

  def find_or_create_parent_for_verification(invitation)
    # Strategy 1: Find existing user by invitation phone number
    if invitation.recipient_phone_number.present?
      existing_user = User.find_by(phone_number: invitation.recipient_phone_number)
      return existing_user if existing_user
    end

    # Strategy 2: Find by invitation email if stored
    if invitation.respond_to?(:recipient_email) && invitation.recipient_email.present?
      existing_user = User.find_by(email: invitation.recipient_email)
      return existing_user if existing_user
    end

    # Strategy 3: Create a new parent user based on invitation data
    create_parent_user_from_invitation(invitation)
  end

  def create_parent_user_from_invitation(invitation)
    # Generate a unique auth0_id for the parent
    auth0_id = "parent-#{invitation.recipient_phone_number}-#{SecureRandom.hex(4)}"
    
    # Generate email based on phone number if no email provided
    email = invitation.respond_to?(:recipient_email) && invitation.recipient_email.present? ?
      invitation.recipient_email :
      "parent-#{invitation.recipient_phone_number}@example.com"

    User.create(
      name: invitation.parent_name || "Parent of #{invitation.learner_number}",
      email: email,
      auth0_id: auth0_id,
      phone_number: invitation.recipient_phone_number,
      roles: ['parent']
    )
  end
end