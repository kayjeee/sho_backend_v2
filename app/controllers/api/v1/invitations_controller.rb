# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  # 🔓 PUBLIC CONTROLLER (no authentication required)
  # Rate limiting for public endpoints
  before_action :rate_limit_public_endpoints, only: [:verify_with_details, :verify, :create]

  # ============================================================
  # PUBLIC ENDPOINTS
  # ============================================================

  # ------------------------------------------------------------
  # GET /api/v1/invitations/:token/verify_with_details
  # Verify invitation token & return invitation details
  # ------------------------------------------------------------
  # ------------------------------------------------------------
  # GET /api/v1/invitations/:token
  # Alias for verify_with_details to support standard REST
  # ------------------------------------------------------------
  def show
    verify_with_details
  end

  # ------------------------------------------------------------
  # GET /api/v1/invitations/:token/verify_with_details
  # Verify invitation token & return invitation details
  # ------------------------------------------------------------
  def verify_with_details
    token = params[:token] || params[:id]
    Rails.logger.info "🔍 [InvitationsController] verify_with_details called for token: #{token}"
    
    invitation = find_invitation_by_token(token)
    
    if invitation.nil?
      Rails.logger.warn "❌ No invitation found for token: #{token}"
      return render_error('Invalid or expired invitation link.', [], status: :not_found)
    end
    
    Rails.logger.info "✅ Found invitation: #{invitation.class.name}##{invitation.id}"
    
    # Validate invitation status
    validation_result = validate_invitation_status(invitation)
    return validation_result if validation_result
    
    # Get expiration info
    expiration_date = extract_expiration_date(invitation)
    is_expired = check_if_expired(invitation, expiration_date)
    expires_in = calculate_expires_in(expiration_date)
    
    # Generate response
    render_success(data: {
      invitation: safe_invitation_hash(invitation),
      expires_in: expires_in,
      is_expired: is_expired
    })
    
  rescue StandardError => e
    handle_exception(e, "Invitation verification failed")
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations
  # Create a new invitation
  # ------------------------------------------------------------
  def create
    Rails.logger.info "📥 [InvitationsController] Creating invitation"
    
    # Extract and validate parameters
    service_params = extract_invitation_params
    sender = find_sender(service_params[:sender_id])
    
    # Build service parameters
    service_params = build_service_params(service_params, sender)
    
    Rails.logger.info "🔧 Service params: #{service_params.except(:phone_number)}"
    
    # Call invitation service
    result = UserServices::InvitationService.new(service_params).call

    Rails.logger.info "📊 Service result - Success: #{result.success}, Errors: #{result.errors}"

    if result.success
      invitation = result.invitation
      magic_link = generate_magic_link(invitation)
      
      log_invitation_created(invitation, magic_link)
      
      render_success(
        message: 'Invitation sent successfully.',
        data: {
          invitation: safe_invitation_hash(invitation),
          magic_link: magic_link
        },
        status: :created
      )
    else
      render_error('Invitation creation failed', result.errors)
    end
    
  rescue StandardError => e
    handle_exception(e, "Invitation creation failed")
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/verify
  # Verify & accept invitation, linking parent to learners
  # ------------------------------------------------------------
  def verify
    Rails.logger.info "🔍 [InvitationsController] Verifying invitation"
    Rails.logger.info "   Token: #{params[:token]}, Auth0 ID: #{params[:auth0_id]}"
    
    # Validate required parameters
    return render_error('Missing auth0_id') unless params[:auth0_id].present?
    return render_error('Missing token') unless params[:token].present?

    # Find invitation
    invitation = find_invitation_by_token(params[:token])
    return render_error('Invitation not found') unless invitation

    # Validate invitation status
    validation_result = validate_invitation_for_acceptance(invitation)
    return validation_result if validation_result

    # Find learners associated with invitation
    learners = find_invitation_learners(invitation)

    # ✅ FIX: Only error out if it's NOT a TeacherInvitation
    if learners.blank? && !invitation.is_a?(TeacherInvitation)
      Rails.logger.error "❌ No learners found for invitation: #{invitation.id}"
      return render_error('Learners not found for this invitation')
    end
    
    Rails.logger.info "✅ Found #{learners.count} learner(s) for invitation"

    # Process invitation acceptance
    process_invitation_acceptance(invitation, learners, params[:auth0_id])
    
    # Log success
    log_invitation_accepted(invitation, learners)

    # Return success response
    render_success(
      message: 'Invitation accepted successfully',
      data: {
        learners: learners.map { |l| safe_learner_hash(l) },
        invitation: safe_invitation_hash(invitation)
      }
    )
    
  rescue StandardError => e
    handle_exception(e, "Invitation verification failed")
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/bulk_create
  # Create multiple invitations at once
  # ------------------------------------------------------------
  def bulk_create
    Rails.logger.info "📦 [InvitationsController] Bulk create request"
    Rails.logger.info "   Invitations count: #{bulk_params[:invitations]&.size || 0}"

    # Validate bulk parameters
    if bulk_params[:invitations].blank?
      return render_error('No invitations provided')
    end

    # Find sender user
    sender = find_sender(bulk_params[:sender_id])
    
    Rails.logger.info "   Sender: #{sender&.auth0_id || 'nil'}"

    # Process bulk invitations
    result = UserServices::BulkInvitationService.new(
      sender: sender,
      invitations_data: bulk_params[:invitations],
      role: bulk_params[:role] || 'parent',
      school_id: bulk_params[:school_id],
      invited_via: bulk_params[:invited_via] || 'whatsapp'
    ).call

    # Handle response based on result
    if result.success
      handle_bulk_success(result)
    else
      handle_bulk_partial_failure(result)
    end
    
  rescue StandardError => e
    handle_exception(e, "Bulk invitation creation failed")
  end

  # ============================================================
  # PRIVATE METHODS
  # ============================================================

  private

  # ------------------------------------------------------------
  # STRONG PARAMETERS
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
  rescue ActionController::ParameterMissing => e
    Rails.logger.warn "⚠️ Missing invitation parameter: #{e.message}"
    params.permit(
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
      :country_code,
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
  # PARAMETER EXTRACTION
  # ------------------------------------------------------------
  def extract_invitation_params
    {
      sender_id: params[:sender_id] || params.dig(:invitation, :sender_id),
      phone_number: params[:phone_number] || params.dig(:invitation, :phone_number),
      school_id: params[:school_id] || params.dig(:invitation, :school_id),
      learner_number: params[:learner_number] || params.dig(:invitation, :learner_number),
      learner_numbers: params[:learner_numbers] || params.dig(:invitation, :learner_numbers),
      role: params[:role] || params.dig(:invitation, :role) || 'parent',
      parent_name: params[:parent_name] || params.dig(:invitation, :parent_name),
      grade_id: params[:grade_id] || params.dig(:invitation, :grade_id),
      invited_via: params[:invited_via] || params.dig(:invitation, :invited_via) || 'whatsapp',
      country_code: params[:country_code] || params.dig(:invitation, :country_code) || '27',
      country_name: params[:country_name] || params.dig(:invitation, :country_name) || 'South Africa'
    }
  end

  def build_service_params(params, sender)
    {
      sender: sender,
      phone_number: params[:phone_number],
      school_id: params[:school_id],
      learner_number: params[:learner_number],
      learner_numbers: params[:learner_numbers],
      role: params[:role],
      parent_name: params[:parent_name],
      grade_id: params[:grade_id],
      invited_via: params[:invited_via],
      country_code: params[:country_code],
      country_name: params[:country_name]
    }.compact
  end

  # ------------------------------------------------------------
  # INVITATION LOOKUP
  # ------------------------------------------------------------
  def find_invitation_by_token(token)
    return nil if token.blank?
    
    Rails.logger.debug "🔍 Searching for token in all invitation collections: #{token}"
    
    # Search in order of likelihood (with status filter)
    # Note: TeacherInvitation uses hashed tokens, so we use its custom finder
    invitation = Invitation.where(token: token, status: 'pending').first ||
                 LearnerInvitation.where(token: token, status: 'pending').first ||
                 TeacherInvitation.find_by_token(token)
    
    # Fallback: search without status filter (if not already found)
    unless invitation
      invitation = Invitation.where(token: token).first ||
                   LearnerInvitation.where(token: token).first
    end
    
    invitation
  end

  # ------------------------------------------------------------
  # INVITATION VALIDATION
  # ------------------------------------------------------------
  def validate_invitation_status(invitation)
    expiration_date = extract_expiration_date(invitation)
    is_expired = check_if_expired(invitation, expiration_date)

    if is_expired
      Rails.logger.warn "⚠️ Invitation expired: #{invitation.id}"
      return render_error('Invitation has expired.', [], status: :gone)
    end

    # Handle both pending? method and status string check
    is_pending = if invitation.respond_to?(:pending?)
      invitation.pending?
    else
      invitation.status == 'pending'
    end

    unless is_pending
      Rails.logger.warn "⚠️ Invitation not pending: #{invitation.id}, status: #{invitation.status}"
      return render_error("Invitation has already been #{invitation.status}.", [], status: :conflict)
    end

    nil
  end

  def validate_invitation_for_acceptance(invitation)
    expiration_date = extract_expiration_date(invitation)
    is_expired = check_if_expired(invitation, expiration_date)

    if is_expired
      return render_error('Invitation has expired')
    end

    is_pending = if invitation.respond_to?(:pending?)
      invitation.pending?
    else
      invitation.status == 'pending'
    end

    unless is_pending
      return render_error("Invitation has already been #{invitation.status}")
    end

    nil
  end

  # ------------------------------------------------------------
  # EXPIRATION HANDLING
  # ------------------------------------------------------------
  def extract_expiration_date(invitation)
    if invitation.respond_to?(:expires_at)
      invitation.expires_at
    elsif invitation.respond_to?(:expired_at)
      invitation.expired_at
    else
      nil
    end
  end

  def check_if_expired(invitation, expiration_date)
    if invitation.respond_to?(:expired?)
      invitation.expired?
    else
      expiration_date && expiration_date < Time.current
    end
  end

  def calculate_expires_in(expiration_date)
    expiration_date ? (expiration_date - Time.current).to_i : nil
  end

  # ------------------------------------------------------------
  # LEARNER LOOKUP
  # ------------------------------------------------------------
  def find_invitation_learners(invitation)
    # ✅ FIX: Teachers don't have associated learners in the same way parents do
    return [] if invitation.is_a?(TeacherInvitation)

    Rails.logger.info "🔍 Finding learners for invitation: #{invitation.id}"
    
    # Strategy 1: Direct learner IDs
    if invitation.respond_to?(:learner_ids) && invitation.learner_ids.present? && invitation.learner_ids.any?
      learners = Learner.where(:id.in => invitation.learner_ids).to_a
      if learners.present?
        Rails.logger.info "✅ Found #{learners.count} learner(s) by ID"
        return learners
      end
    end

    # Strategy 2: Accession numbers
    numbers = extract_learner_numbers(invitation)
    if numbers.any?
      learners = find_learners_by_accession_numbers(invitation, numbers)
      return learners if learners.present?
    end

    # Strategy 3: Phone number fallback
    learners = find_learners_by_phone(invitation)
    return learners if learners.present?

    Rails.logger.warn "⚠️ No learners found using any strategy"
    []
  end

  def extract_learner_numbers(invitation)
    numbers = []
    
    if invitation.respond_to?(:learner_numbers) && invitation.learner_numbers.present?
      numbers += Array(invitation.learner_numbers)
    end
    
    if invitation.respond_to?(:learner_number) && invitation.learner_number.present?
      numbers << invitation.learner_number
    end
    
    numbers.compact.uniq
  end

  def find_learners_by_accession_numbers(invitation, numbers)
    Rails.logger.info "🔍 Searching by accession numbers: #{numbers}"
    
    learners = Learner.where(
      school_id: invitation.school_id.to_s,
      :accessionNumber.in => numbers
    ).to_a
    
    if learners.present?
      Rails.logger.info "✅ Found #{learners.count} learner(s) by accession number"
    end
    
    learners
  end

  def find_learners_by_phone(invitation)
    return [] unless invitation.respond_to?(:recipient_phone_number) && 
                    invitation.recipient_phone_number.present?

    phone = invitation.recipient_phone_number
    phone_variations = normalize_phone(phone)
    
    Rails.logger.info "🔍 Searching by phone variations: #{phone_variations}"
    
    Learner.where(school_id: invitation.school_id.to_s).any_of(
      { phone: { '$in' => phone_variations } },
      { telHome: { '$in' => phone_variations } },
      { telEmergency: { '$in' => phone_variations } }
    ).to_a
  end

  # ------------------------------------------------------------
  # PHONE NUMBER UTILITIES
  # ------------------------------------------------------------
  def normalize_phone(phone)
    return [] if phone.blank?
    
    phone = phone.to_s.strip
    variations = [phone]

    # South Africa specific normalization
    if phone.start_with?('27')
      variations << "0#{phone[2..]}"
    elsif phone.start_with?('0')
      variations << "27#{phone[1..]}"
    end

    variations.uniq
  end

  # ------------------------------------------------------------
  # INVITATION PROCESSING
  # ------------------------------------------------------------
  def process_invitation_acceptance(invitation, learners, auth0_id)
    if invitation.is_a?(TeacherInvitation)
      link_teacher_to_grades(invitation, auth0_id)
    else
      link_parent_to_learners(learners, auth0_id)
    end
    update_user_from_invitation(auth0_id, invitation)
    mark_invitation_accepted(invitation)
  end

  def link_teacher_to_grades(invitation, auth0_id)
    user = User.find_by(auth0_id: auth0_id)
    return unless user

    grade_ids = invitation.grade_ids.presence || [invitation.grade_id].compact
    grade_ids.each do |gid|
      TeacherGradeAssignment.find_or_create_by!(
        teacher: user,
        grade_id: gid,
        school_id: invitation.school_id,
        role_type: 'primary',
        assigned_by: invitation.sender || user,
        status: 0
      )
    end
  end

  def link_parent_to_learners(learners, parent_auth0_id)
    Rails.logger.info "🔗 Linking parent #{parent_auth0_id} to #{learners.count} learner(s)"
    
    learners.each do |learner|
      begin
        learner.add_parent(parent_auth0_id)
        Rails.logger.debug "   ↳ Linked to learner #{learner.accessionNumber}"
      rescue => e
        Rails.logger.error "❌ Failed to link parent to learner #{learner.id}: #{e.message}"
      end
    end
  end

  def update_user_from_invitation(auth0_id, invitation)
    user = User.find_by(auth0_id: auth0_id)
    return unless user

    user.school_ids ||= []
    user.school_ids |= [invitation.school_id.to_s]
    
    # ✅ ROLE LOGIC: Add the role from the invitation if it's not already there
    if invitation.respond_to?(:role) && invitation.role.present?
      user.roles ||= []
      user.roles |= [invitation.role.to_s.downcase] # Use lowercase for consistency
    end

    # Only update if blank (don't overwrite existing data)
    user.phone_number ||= invitation.recipient_phone_number if invitation.respond_to?(:recipient_phone_number)
    user.invited_via ||= invitation.invited_via if invitation.respond_to?(:invited_via)
    
    if user.changed?
      user.save
      Rails.logger.info "📝 Updated user #{auth0_id} from invitation (Roles: #{user.roles})"
    end
  end

  def mark_invitation_accepted(invitation)
    invitation.update!(
      status: 'accepted',
      accepted_at: Time.current
    )
    Rails.logger.info "✅ Marked invitation #{invitation.id} as accepted"
  end

  # ------------------------------------------------------------
  # RESPONSE HANDLING
  # ------------------------------------------------------------
  def safe_invitation_hash(invitation)
    begin
      invitation.to_api_hash
    rescue => e
      Rails.logger.error "❌ Error generating invitation hash: #{e.message}"
      {
        id: invitation.id.to_s,
        token: invitation.token,
        status: invitation.status,
        school_id: invitation.school_id,
        error: "Could not generate full invitation details"
      }
    end
  end

  def safe_learner_hash(learner)
    begin
      learner.to_api_hash
    rescue => e
      Rails.logger.error "❌ Error generating learner hash: #{e.message}"
      {
        id: learner.id.to_s,
        accessionNumber: learner.accessionNumber,
        error: "Could not generate full learner details"
      }
    end
  end

  # ------------------------------------------------------------
  # BULK OPERATION HANDLERS
  # ------------------------------------------------------------
  def handle_bulk_success(result)
    Rails.logger.info "✅ Bulk creation successful: #{result.stats[:successful]}/#{result.stats[:total]}"
    
    # 🔍 DEBUG: Log each invitation and its magic link
    result.invitations.each do |inv|
      magic_link = generate_magic_link(inv)
      Rails.logger.info "🔗 Invitation #{inv.id}: Token=#{inv.token}"
      Rails.logger.info "🔗 Magic Link: #{magic_link}"
    end
    
    render_success(
      message: "Successfully created #{result.stats[:successful]} invitations",
      data: {
        invitations: result.invitations.map { |inv| safe_invitation_hash(inv) },
        stats: result.stats,
        magic_links: result.invitations.map { |inv| generate_magic_link(inv) }
      },
      status: :created
    )
  end

  def handle_bulk_partial_failure(result)
    Rails.logger.warn "⚠️ Bulk creation completed with failures: #{result.stats[:failed]}/#{result.stats[:total]}"
    
    status_code = result.stats[:failed] == result.stats[:total] ? :unprocessable_entity : :multi_status
    
    render_success(
      message: "Bulk invitation completed with some failures",
      data: {
        invitations: result.invitations.map { |inv| safe_invitation_hash(inv) },
        stats: result.stats,
        errors: result.errors
      },
      status: status_code
    )
  end

  # ------------------------------------------------------------
  # SENDER LOOKUP
  # ------------------------------------------------------------
  def find_sender(sender_id)
    return nil unless sender_id.present?
    
    user = User.find_by(auth0_id: sender_id)
    if user.nil?
      Rails.logger.warn "⚠️ Sender not found with auth0_id: #{sender_id}"
    end
    user
  end

  # ------------------------------------------------------------
  # MAGIC LINK GENERATION
  # ------------------------------------------------------------
  def generate_magic_link(invitation)
    school_name = safe_school_name(invitation)
    token = invitation.is_a?(Hash) ? invitation[:token] : invitation.token
    
    # ✅ VALIDATION: Ensure neither token nor school_name is nil/undefined
    if token.blank?
      Rails.logger.error "❌ Cannot generate magic link: token is blank"
      return nil
    end
    
    if school_name.blank? || school_name == 'Unknown School'
      Rails.logger.warn "⚠️ Generating magic link with fallback school name"
    end
    
    "https://www.schoolheadoffice.com/parent?token=#{token}&school=#{URI.encode_www_form_component(school_name)}"
  end

  def safe_school_name(invitation)
    begin
      if invitation.is_a?(Hash)
        'Unknown School'
      elsif invitation.respond_to?(:school_name)
        invitation.school_name
      else
        'Unknown School'
      end
    rescue => e
      Rails.logger.error "❌ Error getting school name: #{e.message}"
      'Unknown School'
    end
  end

  # ------------------------------------------------------------
  # LOGGING UTILITIES
  # ------------------------------------------------------------
  def log_invitation_created(invitation, magic_link)
    Rails.logger.info "✅ Invitation created: #{invitation.id}"
    Rails.logger.info "   ↳ Token: #{invitation.token}"
    Rails.logger.info "   ↳ Magic Link: #{magic_link}"
  end

  def log_invitation_accepted(invitation, learners)
    Rails.logger.info "✅ Invitation accepted: #{invitation.id}"
    Rails.logger.info "   ↳ Parent linked to #{learners.count} learner(s)"
    Rails.logger.info "   ↳ Learners: #{learners.map(&:accessionNumber).join(', ')}"
  end

  def log_error(context, error)
    Rails.logger.error "❌ [InvitationsController] #{context}:"
    Rails.logger.error "   Message: #{error.message}"
    Rails.logger.error "   Backtrace:"
    error.backtrace.first(10).each do |line|
      Rails.logger.error "     #{line}"
    end
  end

  # ------------------------------------------------------------
  # ERROR HANDLING
  # ------------------------------------------------------------
  def format_errors_for_user(errors)
    if errors.is_a?(Array)
      errors.join(', ')
    elsif errors.is_a?(Hash)
      errors.full_messages.join(', ')
    else
      errors.to_s
    end
  end


  # ------------------------------------------------------------
  # RATE LIMITING
  # ------------------------------------------------------------
  def rate_limit_public_endpoints
    # Implement your rate limiting logic here
    # Example: Rack::Attack or custom logic
    Rails.logger.debug "📊 Rate limiting check for #{action_name} from IP: #{request.remote_ip}"
  end
end