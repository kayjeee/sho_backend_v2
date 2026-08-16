# app/controllers/api/v1/invitations_controller.rb
class Api::V1::InvitationsController < ApplicationController
  # 🔓 PUBLIC CONTROLLER (no authentication required)
  before_action :rate_limit_public_endpoints, only: [:verify_with_details, :verify, :create]

  # ============================================================
  # PUBLIC ENDPOINTS
  # ============================================================

  # ------------------------------------------------------------
  # GET /api/v1/invitations/:token/verify_with_details
  # Verify invitation token & return invitation details
  # ------------------------------------------------------------
  def verify_with_details
    Rails.logger.info "🔍 [InvitationsController] verify_with_details called for token: #{params[:token]}"
    
    invitation = find_invitation_by_token(params[:token])
    
    if invitation.nil?
      Rails.logger.warn "❌ No invitation found for token: #{params[:token]}"
      return render json: {
        success: false,
        message: 'Invalid or expired invitation link.'
      }, status: :not_found
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
    render json: {
      success: true,
      invitation: safe_invitation_hash(invitation),
      expires_in: expires_in,
      is_expired: is_expired
    }, status: :ok
    
  rescue StandardError => e
    log_error("Invitation verification failed", e)
    render json: {
      success: false,
      message: 'Failed to verify invitation. Please try again.'
    }, status: :internal_server_error
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations
  # Create a new invitation
  # ------------------------------------------------------------
  def create
    Rails.logger.info "📥 [InvitationsController] Creating invitation"
    
    # Don't use params[:invitation] — ParamsWrapper only auto-includes keys that
    # literally match the Invitation model's field names (recipient_phone_number,
    # sender_id), so it silently drops phone_number/sender since those don't match.
    raw_hash = params.to_unsafe_h
    service_params = normalize_hash_keys(raw_hash)

    # Accept both sender_id (backend standard) and sender (NextJS client contract)
    sender = find_sender(service_params[:sender_id] || service_params[:sender])
    
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
      
      render json: {
        success: true,
        message: 'Invitation sent successfully.',
        invitation: safe_invitation_hash(invitation),
        magic_link: magic_link
      }, status: :created
    else
      Rails.logger.error "❌ Invitation creation failed with errors: #{result.errors}"
      render json: {
        success: false,
        errors: result.errors,
        message: format_errors_for_user(result.errors)
      }, status: :unprocessable_entity
    end
    
  rescue StandardError => e
    log_error("Invitation creation failed", e)
    render json: {
      success: false,
      message: 'Failed to create invitation. Please try again.',
      error: Rails.env.development? ? e.message : nil
    }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/verify
  # Verify & accept invitation, linking parent to learners
  # ------------------------------------------------------------
  def verify
    Rails.logger.info "🔍 [InvitationsController] Verifying/Accepting invitation"
    
    # Normalize keys in parameters
    norm_params = normalize_hash_keys(params)
    token = norm_params[:token]
    auth0_id = norm_params[:auth0_id]

    Rails.logger.info "   Token: #{token}, Auth0 ID: #{auth0_id}"
    
    # Validate required parameters
    return render_error('Missing auth0_id') if auth0_id.blank?
    return render_error('Missing token') if token.blank?

    # Delegate the heavy lifting to AcceptInvitationService
    result = UserServices::AcceptInvitationService.new(
      token: token,
      auth0_id: auth0_id
    ).call

    if result.success?
      link_parent_to_learners(result.learners, result.invitation)

      render json: {
        success: true,
        message: 'Invitation accepted successfully',
        learners: result.learners.map { |l| safe_learner_hash(l) },
        invitation: safe_invitation_hash(result.invitation)
      }, status: :ok
    else
      Rails.logger.error "❌ Acceptance failed: #{result.errors}"
      render json: {
        success: false,
        errors: result.errors,
        message: result.errors.join(", ")
      }, status: :unprocessable_entity
    end
    
  rescue StandardError => e
    log_error("Invitation acceptance transaction failed", e)
    render_error("Failed to accept invitation: #{e.message}")
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/match_by_phone
  # Match and accept invitations by phone number for parent setup
  # ------------------------------------------------------------
  def match_by_phone
    Rails.logger.info "📞 [InvitationsController] match_by_phone called"

    phone_number = params[:phone_number].presence || params[:phoneNumber]
    auth0_id = params[:auth0_id].presence || params[:auth0Id]
    school_id = params[:school_id].presence || params[:schoolId]

    if phone_number.blank? || auth0_id.blank? || school_id.blank?
      return render json: {
        success: false,
        message: "Missing required parameters. phone_number, auth0_id, and school_id are required."
      }, status: :bad_request
    end

    parent_user = begin
      User.where(auth0_id: auth0_id).first
    rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
      nil
    end

    if parent_user.nil?
      return render json: {
        success: false,
        message: "No User found for the given auth0_id: #{auth0_id}"
      }, status: :not_found
    end

    input_norm = normalize_phone_to_last_9(phone_number)
    if input_norm.blank?
      return render json: {
        success: false,
        message: "Invalid phone number format."
      }, status: :unprocessable_entity
    end

    pending_invitations = Invitation.by_school(school_id).pending.to_a

    matching_invitations = pending_invitations.select do |inv|
      normalize_phone_to_last_9(inv.recipient_phone_number) == input_norm
    end

    matched_invitations_serialized = []

    matching_invitations.each do |invitation|
      result = UserServices::AcceptInvitationService.new(
        token: invitation.token,
        auth0_id: auth0_id
      ).call

      if result.success?
        link_parent_to_learners(result.learners, result.invitation)
        matched_invitations_serialized << safe_invitation_hash(result.invitation)
      else
        Rails.logger.warn "⚠️ Failed to process invitation #{invitation.id} in match_by_phone: #{result.errors}"
        matched_invitations_serialized << {
          id: invitation.id.to_s,
          success: false,
          error: result.errors.join(", "),
          errors: result.errors,
          token: invitation.token,
          status: invitation.status
        }
      end
    end

    render json: {
      success: true,
      matched_count: matching_invitations.size,
      invitations: matched_invitations_serialized
    }, status: :ok
  rescue StandardError => e
    log_error("Failed to match invitations by phone", e)
    render json: {
      success: false,
      message: "An error occurred: #{e.message}"
    }, status: :internal_server_error
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/bulk_create
  # Create multiple invitations at once
  # ------------------------------------------------------------
  def bulk_create
    Rails.logger.info "📦 [InvitationsController] Bulk create request"

    # Normalize parameters
    norm_params = normalize_hash_keys(params)
    invitations_data = norm_params[:invitations]

    Rails.logger.info "   Invitations count: #{invitations_data&.size || 0}"

    # Validate bulk parameters
    if invitations_data.blank?
      return render json: {
        success: false,
        message: 'No invitations provided'
      }, status: :unprocessable_entity
    end

    # Find sender user
    sender = find_sender(norm_params[:sender_id])
    
    Rails.logger.info "   Sender: #{sender&.auth0_id || 'nil'}"

    # Process bulk invitations
    result = UserServices::BulkInvitationService.new(
      sender: sender,
      invitations_data: invitations_data,
      role: norm_params[:role] || 'parent',
      school_id: norm_params[:school_id],
      invited_via: norm_params[:invited_via] || 'whatsapp'
    ).call

    # Handle response based on result
    if result.success
      handle_bulk_success(result)
    else
      handle_bulk_partial_failure(result)
    end
    
  rescue StandardError => e
    log_error("Bulk invitation creation failed", e)
    render json: {
      success: false,
      message: 'Failed to create bulk invitations. Please try again.',
      error: Rails.env.development? ? e.message : nil,
      invitations: []
    }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------
  # GET /api/v1/invitations
  # List invitations for a school
  # ------------------------------------------------------------
  def index
    school_id = params[:school_id] || params[:schoolId]
    if school_id.blank?
      return render json: { success: false, message: 'Missing required parameter: school_id' }, status: :bad_request
    end

    invitations_scope = Invitation.by_school(school_id)

    status_param = params[:status] || params[:statusId]
    if status_param.present? && status_param != 'all'
      status_str = status_param.to_s.downcase
      if %w[pending accepted expired rejected cancelled].include?(status_str)
        invitations_scope = invitations_scope.send(status_str)
      else
        invitations_scope = invitations_scope.where(status: status_str)
      end
    end

    invitations_scope = invitations_scope.recent
    total_count = invitations_scope.count
    serialized_invitations = invitations_scope.map { |inv| safe_invitation_hash(inv) }

    render json: {
      success: true,
      invitations: serialized_invitations,
      total: total_count
    }, status: :ok
  rescue StandardError => e
    log_error("Failed to list invitations", e)
    render json: { success: false, message: "Failed to fetch invitations: #{e.message}" }, status: :internal_server_error
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/:token/resend
  # Resend invitation by regenerating token & resetting status/expiry
  # ------------------------------------------------------------
  def resend
    token = params[:token] || params[:id]
    invitation = Invitation.find_by_token(token)

    if invitation.nil?
      return render json: { success: false, message: "Invitation not found" }, status: :not_found
    end

    if invitation.resend!
      render json: { success: true, invitation: safe_invitation_hash(invitation) }, status: :ok
    else
      render json: { success: false, message: "Failed to resend invitation" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    log_error("Failed to resend invitation", e)
    render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/:token/cancel
  # Cancel invitation by token
  # ------------------------------------------------------------
  def cancel
    token = params[:token] || params[:id]
    invitation = Invitation.find_by_token(token)

    if invitation.nil?
      return render json: { success: false, message: "Invitation not found" }, status: :not_found
    end

    if invitation.cancel!
      render json: { success: true, invitation: safe_invitation_hash(invitation) }, status: :ok
    else
      render json: { success: false, message: "Failed to cancel invitation" }, status: :unprocessable_entity
    end
  rescue StandardError => e
    log_error("Failed to cancel invitation", e)
    render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
  end

  # ------------------------------------------------------------
  # POST /api/v1/invitations/:token/admin_accept
  # Admin-triggered accept action without parent auth0_id
  # ------------------------------------------------------------
  def admin_accept
    token = params[:token] || params[:id]
    invitation = Invitation.find_by_token(token)

    if invitation.nil?
      return render json: { success: false, message: "Invitation not found" }, status: :not_found
    end

    phone = invitation.recipient_phone_number.to_s.strip
    variations = [phone]
    if phone.start_with?('27')
      variations << "0#{phone[2..]}"
    elsif phone.start_with?('0')
      variations << "27#{phone[1..]}"
    end

    parent_user = User.where(:phone_number.in => variations).first ||
                  User.where(:phone.in => variations).first

    if parent_user.blank?
      return render json: {
        success: false,
        message: "No parent account found for this phone number yet — the parent must sign up first before this invitation can be linked."
      }, status: :unprocessable_entity
    end

    # Delegate the heavy lifting to AcceptInvitationService
    result = UserServices::AcceptInvitationService.new(
      token: invitation.token,
      auth0_id: parent_user.auth0_id
    ).call

    if result.success?
      link_parent_to_learners(result.learners, result.invitation)

      render json: {
        success: true,
        invitation: safe_invitation_hash(result.invitation),
        learners: result.learners.map { |l| safe_learner_hash(l) }
      }, status: :ok
    else
      render json: {
        success: false,
        errors: result.errors,
        message: result.errors.join(", ")
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    log_error("Admin acceptance failed", e)
    render json: { success: false, message: "An error occurred: #{e.message}" }, status: :internal_server_error
  end

  # ============================================================
  # PRIVATE METHODS
  # ============================================================

  private

  # Recursively normalizes camelCase keys to snake_case symbols for backend compatibility
  def normalize_hash_keys(hash)
    return hash unless hash.is_a?(Hash) || hash.is_a?(ActionController::Parameters)

    normalized = {}
    hash.each do |key, value|
      snake_key = key.to_s.underscore.to_sym

      if value.is_a?(Array)
        normalized[snake_key] = value.map { |v| v.is_a?(Hash) || v.is_a?(ActionController::Parameters) ? normalize_hash_keys(v) : v }
      elsif value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
        normalized[snake_key] = normalize_hash_keys(value)
      else
        normalized[snake_key] = value
      end
    end
    normalized
  end

  # ------------------------------------------------------------
  # PARAMETER EXTRACTION
  # ------------------------------------------------------------
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
    invitation = Invitation.where(token: token, status: 'pending').first ||
                 LearnerInvitation.where(token: token, status: 'pending').first ||
                 TeacherInvitation.where(token: token, status: 'pending').first
    
    # Fallback: search without status filter
    invitation ||= Invitation.where(token: token).first ||
                   LearnerInvitation.where(token: token).first ||
                   TeacherInvitation.where(token: token).first
    
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
      return render json: {
        success: false,
        message: 'Invitation has expired.'
      }, status: :gone
    end
    
    # Resilient check for pending status across all invitation models
    is_pending = invitation.respond_to?(:pending?) ? invitation.pending? : (invitation.status == 'pending' || invitation.status == 0)
    unless is_pending
      Rails.logger.warn "⚠️ Invitation not pending: #{invitation.id}, status: #{invitation.status}"
      return render json: {
        success: false,
        message: "Invitation has already been processed."
      }, status: :conflict
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
      return false if expiration_date.blank?
      exp_time = expiration_date.respond_to?(:to_time) ? expiration_date.to_time : expiration_date
      exp_time < Time.current
    end
  end

  def calculate_expires_in(expiration_date)
    return nil if expiration_date.blank?
    exp_time = expiration_date.respond_to?(:to_time) ? expiration_date.to_time : expiration_date
    (exp_time - Time.current).to_i
  end

  # ------------------------------------------------------------
  # SENDER LOOKUP
  # ------------------------------------------------------------
  def find_sender(sender_id)
    return nil unless sender_id.present?
    
    user = User.find_by(auth0_id: sender_id)
    if user.nil?
      # Try lookup by ObjectId string
      user = User.find(sender_id) if BSON::ObjectId.legal?(sender_id)
    end
    user
  rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
    nil
  end

  # ------------------------------------------------------------
  # MAGIC LINK GENERATION
  # ------------------------------------------------------------
  def generate_magic_link(invitation)
    school_name = safe_school_name(invitation)
    token = invitation.is_a?(Hash) ? invitation[:token] : (invitation.respond_to?(:token) ? invitation.token : invitation.invitation_token)
    
    if token.blank?
      Rails.logger.error "❌ Cannot generate magic link: token is blank"
      return nil
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
    token = invitation.respond_to?(:token) ? invitation.token : invitation.invitation_token
    Rails.logger.info "✅ Invitation created: #{invitation.id}"
    Rails.logger.info "   ↳ Token: #{token}"
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

  def render_error(message, status: :unprocessable_entity)
    render json: {
      success: false,
      message: message
    }, status: status
  end

  # ------------------------------------------------------------
  # RATE LIMITING
  # ------------------------------------------------------------
  def rate_limit_public_endpoints
    Rails.logger.debug "📊 Rate limiting check for #{action_name} from IP: #{request.remote_ip}"
  end

  def safe_invitation_hash(invitation)
    begin
      invitation.to_api_hash
    rescue => e
      Rails.logger.error "❌ Error generating invitation hash: #{e.message}"
      token = invitation.respond_to?(:token) ? invitation.token : invitation.invitation_token
      {
        id: invitation.id.to_s,
        token: token,
        status: invitation.status,
        school_id: invitation.respond_to?(:school_id) ? invitation.school_id : nil,
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

    result.invitations.each do |inv|
      magic_link = generate_magic_link(inv)
      token = inv.respond_to?(:token) ? inv.token : inv.invitation_token
      Rails.logger.info "🔗 Invitation #{inv.id}: Token=#{token}"
      Rails.logger.info "🔗 Magic Link: #{magic_link}"
    end

    render json: {
      success: true,
      message: "Successfully created #{result.stats[:successful]} invitations",
      invitations: result.invitations.map { |inv| safe_invitation_hash(inv) },
      stats: result.stats,
      magic_links: result.invitations.map { |inv| generate_magic_link(inv) }
    }, status: :created
  end

  def handle_bulk_partial_failure(result)
    Rails.logger.warn "⚠️ Bulk creation completed with failures: #{result.stats[:failed]}/#{result.stats[:total]}"

    status_code = result.stats[:failed] == result.stats[:total] ? :unprocessable_entity : :multi_status

    render json: {
      success: result.stats[:failed] < result.stats[:total],
      message: "Bulk invitation completed with some failures",
      invitations: result.invitations.map { |inv| safe_invitation_hash(inv) },
      stats: result.stats,
      errors: result.errors
    }, status: status_code
  end

  # Shared private method to apply grade-force-set logic for a list of learners and an invitation
  def link_parent_to_learners(learners, invitation)
    return if learners.blank? || invitation.blank?

    if invitation.grade_id.present?
      learners.each do |learner|
        begin
          learner.force_grade_id!(invitation.grade_id)
          Rails.logger.info "🏫 [link_parent_to_learners] Force-set learner #{learner.id} grade to #{invitation.grade_id}"
        rescue => e
          Rails.logger.error "❌ [link_parent_to_learners] Failed to force-set learner #{learner.id} grade: #{e.message}"
        end
      end
    end
  end

  def normalize_phone_to_last_9(phone)
    return nil if phone.blank?
    digits = phone.to_s.gsub(/\D/, '')
    digits.length >= 9 ? digits[-9..] : digits
  end
end
