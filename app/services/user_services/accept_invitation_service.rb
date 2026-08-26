# app/services/user_services/accept_invitation_service.rb
module UserServices
  class AcceptInvitationService
    class Result
      attr_reader :success, :invitation, :learners, :errors

      def initialize(success:, invitation: nil, learners: [], errors: [])
        @success = success
        @invitation = invitation
        @learners = learners
        @errors = errors
      end

      def success?
        @success
      end

      def failure?
        !@success
      end
    end

    def initialize(token:, auth0_id:)
      @token = token
      @auth0_id = auth0_id
    end

    def call
      Rails.logger.info "🤝 [AcceptInvitationService] Initializing acceptance for token: #{@token}, Auth0 ID: #{@auth0_id}"

      # 1. Find invitation using resilient token lookup
      invitation = find_invitation_by_token(@token)
      if invitation.nil?
        Rails.logger.warn "❌ [AcceptInvitationService] Invitation not found for token: #{@token}"
        return Result.new(success: false, errors: ["Invitation not found"])
      end

      # 2. Find parent user
      parent_user = User.find_by(auth0_id: @auth0_id)
      if parent_user.nil?
        Rails.logger.warn "❌ [AcceptInvitationService] Parent user not found for Auth0 ID: #{@auth0_id}"
        return Result.new(success: false, errors: ["Parent user not found"])
      end

      # 3. Validate expiration
      expiration_date = extract_expiration_date(invitation)
      is_expired = check_if_expired(invitation, expiration_date)
      if is_expired
        Rails.logger.warn "⚠️ [AcceptInvitationService] Invitation expired: #{invitation.id}"
        return Result.new(success: false, errors: ["Invitation has expired"])
      end

      # 4. Validate status (must be pending / 0)
      # Both String ('pending') and Integer (0) are supported due to the legacy model coexistence
      unless invitation.status == 'pending' || invitation.status == 0
        Rails.logger.warn "⚠️ [AcceptInvitationService] Invitation status not pending: #{invitation.status}"
        return Result.new(success: false, errors: ["Invitation has already been processed (status: #{invitation.status})"])
      end

      # 5. Find associated learners
      learners = find_invitation_learners(invitation)
      if learners.blank?
        Rails.logger.error "❌ [AcceptInvitationService] No learners found for invitation: #{invitation.id}"
        return Result.new(success: false, errors: ["No learners found for this invitation"])
      end

      # 6. Begin transaction/acceptance process
      Rails.logger.info "🔗 [AcceptInvitationService] Linking parent #{parent_user.auth0_id} to #{learners.count} learner(s)"
      learners.each do |learner|
        begin
          learner.add_parent(parent_user)
          Rails.logger.debug "   ↳ Linked to learner: #{learner.full_name} (#{learner.accessionNumber})"
        rescue => e
          Rails.logger.error "❌ [AcceptInvitationService] Failed to link to learner #{learner.id}: #{e.message}"
        end
      end

      # 7. Update parent roles and school associations
      begin
        parent_user.roles ||= []
        parent_user.roles |= ['parent']
        parent_user.roles.delete('guest')

        parent_user.school_ids ||= []
        parent_user.school_ids |= [invitation.school_id.to_s]

        # Sync phone info if present on invitation
        if invitation.respond_to?(:recipient_phone_number) && invitation.recipient_phone_number.present?
          parent_user.phone = invitation.recipient_phone_number if parent_user.respond_to?(:phone=) && parent_user.phone.blank?
          parent_user.phone_number = invitation.recipient_phone_number if parent_user.respond_to?(:phone_number=) && parent_user.phone_number.blank?
        end

        parent_user.save!
        Rails.logger.info "📝 [AcceptInvitationService] Saved user #{parent_user.auth0_id} roles/schools"
      rescue => e
        Rails.logger.error "❌ [AcceptInvitationService] Failed to update parent roles: #{e.message}"
        return Result.new(success: false, errors: ["Failed to update parent user info: #{e.message}"])
      end

      # 8. Mark invitation as accepted
      begin
        if invitation.is_a?(Invitation)
          invitation.accept!
        else
          status_val = (invitation.respond_to?(:status) && invitation.fields['status']&.type == Integer) ? 1 : 'accepted'
          invitation.update!(
            status: status_val,
            accepted_at: Time.current
          )
        end
        Rails.logger.info "✅ [AcceptInvitationService] Marked invitation #{invitation.id} as accepted"
      rescue => e
        Rails.logger.error "❌ [AcceptInvitationService] Failed to update invitation status: #{e.message}"
      end

      # 9. Complete onboarding stepper step (if applicable)
      begin
        if parent_user.respond_to?(:ensure_onboarding_status)
          parent_user.ensure_onboarding_status
          if parent_user.onboarding_status.respond_to?(:complete_step!)
            parent_user.onboarding_status.complete_step!('link_learner')
          end
        end
      rescue => e
        Rails.logger.warn "⚠️ [AcceptInvitationService] Onboarding sync step completion ignored: #{e.message}"
      end

      Result.new(success: true, invitation: invitation, learners: learners, errors: [])
    end

    private

    def find_invitation_by_token(token)
      return nil if token.blank?

      # Coexistence: Lookup from any collection
      Invitation.where(token: token).first ||
        LearnerInvitation.where(token: token).first ||
        TeacherInvitation.where(token: token).first ||
        LearnerInvitation.where(invitation_token: token).first ||
        TeacherInvitation.where(invitation_token: token).first
    end

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

    def find_invitation_learners(invitation)
      school_id_str = invitation.school_id.to_s
      school_id_bson = BSON::ObjectId.legal?(school_id_str) ? BSON::ObjectId.from_string(school_id_str) : nil
      school_ids = [school_id_str, school_id_bson].compact

      Rails.logger.info "🔍 [AcceptInvitationService#find_invitation_learners] Finding learners for invitation: #{invitation.id}, school_id: #{school_id_str}"

      # Direct learner_ids (if present)
      if invitation.respond_to?(:learner_ids) && invitation.learner_ids.present? && invitation.learner_ids.any?
        Rails.logger.info "   ↳ Attempting match by direct learner_ids: #{invitation.learner_ids}"
        learners = Learner.where(:id.in => invitation.learner_ids).to_a
        Rails.logger.info "     ↳ Match count by learner_ids: #{learners.size}"
        return learners if learners.present?
      end

      # Accession numbers
      numbers = []
      if invitation.respond_to?(:learner_numbers) && invitation.learner_numbers.present?
        numbers += Array(invitation.learner_numbers)
      end
      if invitation.respond_to?(:learner_number) && invitation.learner_number.present?
        numbers << invitation.learner_number
      end
      numbers = numbers.compact.uniq

      if numbers.any?
        Rails.logger.info "   ↳ Attempting match by accession numbers: #{numbers}"
        query = {
          "school_id" => { "$in" => school_ids },
          "$or" => [
            { "accessionNumber" => { "$in" => numbers } },
            { "accession_number" => { "$in" => numbers } }
          ]
        }
        docs = Learner.collection.find(query).to_a
        learners = docs.map { |doc| Learner.instantiate(doc) }
        Rails.logger.info "     ↳ Match count by accession numbers: #{learners.size}"
        return learners if learners.present?
      end

      # Phone variations
      phone = nil
      if invitation.respond_to?(:recipient_phone_number) && invitation.recipient_phone_number.present?
        phone = invitation.recipient_phone_number
      elsif invitation.respond_to?(:learner_phone) && invitation.learner_phone.present?
        phone = invitation.learner_phone
      end

      if phone.present?
        phone_variations = normalize_phone(phone)
        Rails.logger.info "   ↳ Attempting match by phone variations: #{phone_variations}"
        query = {
          "school_id" => { "$in" => school_ids },
          "$or" => [
            { "phone" => { "$in" => phone_variations } },
            { "telHome" => { "$in" => phone_variations } },
            { "telEmergency" => { "$in" => phone_variations } },
            { "whatsapp" => { "$in" => phone_variations } }
          ]
        }
        docs = Learner.collection.find(query).to_a
        learners = docs.map { |doc| Learner.instantiate(doc) }
        Rails.logger.info "     ↳ Match count by phone: #{learners.size}"
        return learners if learners.present?
      end

      Rails.logger.warn "⚠️ [AcceptInvitationService#find_invitation_learners] No learners matched for invitation #{invitation.id}"
      []
    end

    def normalize_phone(phone)
      return [] if phone.blank?
      phone = phone.to_s.strip
      variations = [phone]
      if phone.start_with?('27')
        variations << "0#{phone[2..]}"
      elsif phone.start_with?('0')
        variations << "27#{phone[1..]}"
      end
      variations.uniq
    end
  end
end
