# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  # 🔓 PUBLIC CONTROLLER (no authentication required)

  # ------------------------------------------------------------
  # GET /api/v1/invitations/:token/verify_with_details
  # Verify invitation token & return invitation details
  # ------------------------------------------------------------
  def verify_with_details
    invitation = find_invitation_by_token(params[:token])

    if invitation
      render json: {
        success: true,
        invitation: invitation.to_api_hash
      }, status: :ok
    else
      render_error('Invalid or expired invitation link.', :not_found)
    end
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations
  # Create a single invitation
  # ------------------------------------------------------------
  def create
    Rails.logger.info "📥 Creating invitation with params: #{invitation_params.inspect}"
    Rails.logger.info "👤 Sender user: #{sender_user.inspect}"

    result = UserServices::InvitationService.new(
      sender: sender_user,
      phone_number: get_phone_number,
      school_id: invitation_params[:school_id],
      learner_number: invitation_params[:learner_number],
      learner_numbers: invitation_params[:learner_numbers],
      role: invitation_params[:role],
      parent_name: invitation_params[:parent_name],
      grade_id: invitation_params[:grade_id],
      invited_via: invitation_params[:invited_via],
      country_code: get_country_code,
      country_name: get_country_name
    ).call

    Rails.logger.info "📊 Service result - Success: #{result.success}, Errors: #{result.errors}"

    if result.success
      render json: {
        success: true,
        message: 'Invitation sent successfully.',
        invitation: result.invitation.to_api_hash
      }, status: :created
    else
      render json: {
        success: false,
        errors: result.errors
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    log_error("Invitation creation failed", e)
    render_error('Failed to create invitation. Please try again.')
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/bulk_create
  # Create multiple invitations at once
  # ------------------------------------------------------------
  def bulk_create
    Rails.logger.info "📦 Bulk invitation request received"
    Rails.logger.info "   Invitations count: #{bulk_params[:invitations]&.size || 0}"

    result = UserServices::BulkInvitationService.new(
      sender: sender_user,
      invitations_data: bulk_params[:invitations],
      role: bulk_params[:role] || 'parent',
      school_id: bulk_params[:school_id],
      invited_via: bulk_params[:invited_via] || 'whatsapp'
    ).call

    if result.success
      render json: {
        success: true,
        message: "Successfully created #{result.stats[:successful]} invitations",
        stats: result.stats
      }, status: :created
    else
      render json: {
        success: result.stats[:failed] < result.stats[:total], # Partial success
        message: "Bulk invitation completed with some failures",
        stats: result.stats,
        errors: result.errors
      }, status: result.stats[:failed] == result.stats[:total] ? :unprocessable_entity : :multi_status
    end
  rescue StandardError => e
    log_error("Bulk invitation creation failed", e)
    render_error('Failed to create bulk invitations. Please try again.')
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/verify
  # Verify & accept invitation, linking parent to learners
  # ------------------------------------------------------------
  def verify
    return render_error('Missing auth0_id') unless params[:auth0_id].present?

    invitation = find_invitation_by_token(params[:token])
    return render_error('Invitation not found') unless invitation

    learners = find_invitation_learners(invitation)
    return render_error('Learners not found for this invitation') if learners.blank?

    link_parent_to_learners(learners, params[:auth0_id])
    update_user_from_invitation(params[:auth0_id], invitation)
    mark_invitation_accepted(invitation)

    render json: {
      success: true,
      message: 'Invitation accepted successfully',
      learners: learners.map(&:to_api_hash)
    }, status: :ok
  rescue StandardError => e
    log_error("Invitation verification failed", e)
    render_error('Failed to verify invitation. Please try again.')
  end

  private

  # ------------------------------------------------------------
  # Strong parameters
  # ------------------------------------------------------------
  def invitation_params
    params.require(:invitation).permit(
      :phone_number,
      :school_id,
      :role,
      :invited_via,
      :learner_number,
      :parent_name,
      :sender_id,
      :grade_id,
      :country_code,
      :country_name,
      learner_numbers: []
    )
  end

  def bulk_params
    params.permit(
      :role,
      :school_id,
      :invited_via,
      :sender_id,
      invitations: [
        :phone_number,
        :parent_name,
        :learner_number,
        :grade_id,
        :country_code,
        :country_name,
        learner_numbers: []
      ]
    )
  end

  # ------------------------------------------------------------
  # Extract fields with fallback
  # ------------------------------------------------------------
  def get_phone_number
    invitation_params[:phone_number] || params[:phone_number]
  end

  def get_country_code
    invitation_params[:country_code] || params[:country_code]
  end

  def get_country_name
    invitation_params[:country_name] || params[:country_name]
  end

  # ------------------------------------------------------------
  # Find sender user by auth0_id
  # ------------------------------------------------------------
  def sender_user
    return nil unless invitation_params[:sender_id].present?
    User.find_by(auth0_id: invitation_params[:sender_id])
  end

  # ------------------------------------------------------------
  # Find invitation by token (pending only)
  # ------------------------------------------------------------
  def find_invitation_by_token(token)
    LearnerInvitation.find_by(token: token, status: 'pending') ||
      TeacherInvitation.find_by(token: token, status: 'pending')
  end

  # ------------------------------------------------------------
  # Find learners associated with invitation
  # ------------------------------------------------------------
  def find_invitation_learners(invitation)
    # Strategy 1: Direct learner IDs
    if invitation.learner_ids.present?
      learners = Learner.where(:id.in => invitation.learner_ids)
      return learners if learners.any?
    end

    # Strategy 2: Accession numbers
    numbers = Array(invitation.learner_numbers.presence || invitation.learner_number).compact
    if numbers.any?
      learners = Learner.where(
        school_id: invitation.school_id.to_s,
        :accessionNumber.in => numbers
      )
      return learners if learners.any?
    end

    # Strategy 3: Phone number fallback
    find_learners_by_phone(invitation)
  end

  def find_learners_by_phone(invitation)
    return [] unless invitation.recipient_phone_number.present?

    phone_variations = normalize_phone(invitation.recipient_phone_number)

    Learner.where(school_id: invitation.school_id.to_s).any_of(
      { phone: { '$in' => phone_variations } },
      { telHome: { '$in' => phone_variations } },
      { telEmergency: { '$in' => phone_variations } }
    )
  end

  def normalize_phone(phone)
    variations = [phone]
    if phone.start_with?('27')
      variations << "0#{phone[2..]}"
    elsif phone.start_with?('0')
      variations << "27#{phone[1..]}"
    end
    variations.uniq
  end

  # ------------------------------------------------------------
  # Parent linking & user updates
  # ------------------------------------------------------------
  def link_parent_to_learners(learners, parent_auth0_id)
    learners.each { |learner| learner.add_parent(parent_auth0_id) }
  end

  def update_user_from_invitation(auth0_id, invitation)
    user = User.find_by(auth0_id: auth0_id)
    return unless user

    user.school_ids ||= []
    user.school_ids |= [invitation.school_id.to_s]
    user.phone_number ||= invitation.recipient_phone_number
    user.invited_via ||= invitation.invited_via
    user.save
  end

  def mark_invitation_accepted(invitation)
    invitation.update!(
      status: 'accepted',
      accepted_at: Time.current
    )
  end

  # ------------------------------------------------------------
  # Error handling
  # ------------------------------------------------------------
  def log_error(context, error)
    Rails.logger.error "❌ #{context}: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
  end

  def render_error(message, status: :unprocessable_entity)
    render json: { success: false, message: message }, status: status
  end
end
