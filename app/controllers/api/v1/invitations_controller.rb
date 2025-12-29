# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  # 🔓 PUBLIC CONTROLLER (no authentication)

  # ------------------------------------------------------------
  # Verify invitation token and return invitation details
  # ------------------------------------------------------------
  def verify_with_details
    invitation = Invitation.find_by(token: params[:token], status: 'pending')

    if invitation
      render json: {
        success: true,
        invitation: invitation.to_api_hash
      }, status: :ok
    else
      render json: {
        success: false,
        message: 'Invalid or expired invitation link.'
      }, status: :not_found
    end
  end

  # ------------------------------------------------------------
  # Create an invitation (Public – sender passed explicitly)
  # Supports single and multiple learners
  # ------------------------------------------------------------
  def create
    sender = User.find_by(auth0_id: params[:sender_id])
    return render json: { success: false, errors: ['Sender not found'] }, status: :unprocessable_entity unless sender

    invitation = UserServices::InvitationService.new(
      sender_id: params[:sender_id],
      phone_number: params[:phone_number],
      school_id: params[:school_id],
      learner_number: params[:learner_number],     # ✅ single learner support
      learner_numbers: params[:learner_numbers],   # ✅ multiple learners support
      role: params[:role],
      parent_name: params[:parent_name],
      grade_id: params[:grade_id],
      invited_via: params[:invited_via]
    ).call

    if invitation.persisted?
      render json: {
        success: true,
        message: 'Invitation sent successfully.',
        invitation: invitation.to_api_hash
      }, status: :created
    else
      render json: {
        success: false,
        errors: invitation.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # ------------------------------------------------------------
  # Verify & accept invitation (Public – auth0_id passed explicitly)
  # Works with multiple learners
  # ------------------------------------------------------------
  def verify
    parent_auth0_id = params[:auth0_id]
    return render json: { success: false, message: 'Missing auth0_id' }, status: :unprocessable_entity unless parent_auth0_id.present?

    invitation = Invitation.find_by(token: params[:token])
    return render json: { success: false, message: 'Invitation not found' }, status: :ok unless invitation

    learners = find_invitation_learners(invitation)
    return render json: { success: false, message: "Learner(s) not found: #{Array(invitation.learner_number).join(', ')}" }, status: :ok if learners.blank?

    # Link parent to learners
    learners.each { |learner| learner.add_parent(parent_auth0_id) }

    # Link parent to school, update phone & invited_via if missing
    user = User.find_by(auth0_id: parent_auth0_id)
    if user
      user.school_ids ||= []
      user.school_ids |= [invitation.school_id.to_s]
      user.phone_number = invitation.recipient_phone_number if user.phone_number.blank? && invitation.recipient_phone_number.present?
      user.invited_via = invitation.invited_via if user.invited_via.blank? && invitation.invited_via.present?
      user.save
    end

    # Mark invitation as accepted
    invitation.update(status: 'accepted', accepted_at: Time.current)

    render json: {
      success: true,
      message: 'Invitation accepted successfully',
      learners: learners.map(&:to_api_hash)
    }, status: :ok
  end

  private

  # 🔹 Robust learner lookup for verification
  def find_invitation_learners(invitation)
    # 1️⃣ Try by stored learner IDs (most reliable)
    if invitation.learner_ids.present? && invitation.learner_ids.any?
      learners = Learner.where(:id.in => invitation.learner_ids).to_a
      return learners if learners.present?
    end

    # 2️⃣ Fallback: accessionNumber lookup (handle both ObjectId and String school_id)
    if invitation.learner_number.present? || invitation.learner_numbers.present?
      school_ids = [invitation.school_id, invitation.school_id.to_s]
      learner_numbers = Array(invitation.learner_numbers.presence || invitation.learner_number)
      
      learners = Learner.where(:school_id.in => school_ids)
                        .any_of(*learner_numbers.map { |num| { "accessionNumber" => /^#{Regexp.escape(num)}$/i } })
                        .to_a
      
      return learners if learners.present?
    end

    # 3️⃣ Final fallback: phone numbers (normalized)
    if invitation.recipient_phone_number.present?
      normalized_phones = normalize_phone_numbers(invitation.recipient_phone_number)
      school_ids = [invitation.school_id, invitation.school_id.to_s]

      learners = Learner.where(:school_id.in => school_ids)
                        .any_of(*normalized_phones.flat_map { |phone|
                          [
                            { "phone" => phone },
                            { "telHome" => phone },
                            { "telEmergency" => phone }
                          ]
                        }).to_a
      
      return learners if learners.present?
    end

    []
  end

  # 🔹 Normalize phone numbers (with/without country code)
  def normalize_phone_numbers(phone)
    phones = [phone]
    if phone.start_with?('27')
      phones << "0#{phone[2..-1]}"
    elsif phone.start_with?('0')
      phones << "27#{phone[1..-1]}"
    end
    phones.uniq
  end
end