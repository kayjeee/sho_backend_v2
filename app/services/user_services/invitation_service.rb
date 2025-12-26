# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(sender:, recipient_phone_number:, school_id:, learner_number:, role: 'parent', parent_name: nil, grade_id: nil, invited_via: 'whatsapp')
      @sender = sender
      @recipient_phone_number = recipient_phone_number
      @school_id = school_id
      @learner_number = learner_number
      @role = role
      @parent_name = parent_name
      @grade_id = grade_id
      @invited_via = invited_via
      
      Rails.logger.info "🔹 [InvitationService] Initialized with:"
      Rails.logger.info "   - school_id: #{@school_id}"
      Rails.logger.info "   - learner_number: #{@learner_number}"
      Rails.logger.info "   - parent_name: #{@parent_name}"
      Rails.logger.info "   - invited_via: #{@invited_via}"
    end

    def call
      Rails.logger.info "🔹 [InvitationService] Creating invitation..."

      # 1. Find the school
      school = find_school(@school_id)
      unless school
        Rails.logger.error "❌ [InvitationService] School not found with ID: #{@school_id}"
        invitation = Invitation.new
        invitation.errors.add(:school, "not found with ID: #{@school_id}")
        return invitation
      end
      
      Rails.logger.info "✅ [InvitationService] School found: #{school.schoolName || school.name}"

      # 2. Find ANY learner (don't restrict by school_id since they might be in different school)
      Rails.logger.info "🔍 [InvitationService] Looking for learner with accession number: #{@learner_number}"
      
      # Try different field names: accessionNumber, accession_number, student_id, etc.
      learner = find_learner_by_accession_number(@learner_number)
      
      unless learner
        Rails.logger.error "❌ [InvitationService] Learner not found with number: #{@learner_number}"
        Rails.logger.info "   Available learners in DB: #{Learner.all.map(&:accession_number).compact.first(5)}"
        
        # Create invitation anyway (maybe it's a new learner)
        Rails.logger.info "⚠️ [InvitationService] Creating invitation without linking to existing learner"
        learner = nil
      else
        Rails.logger.info "✅ [InvitationService] Learner found: #{learner.full_name}"
        Rails.logger.info "   Learner school_id: #{learner.school_id}"
        Rails.logger.info "   Request school_id: #{school.id}"
        
        # Check if learner is in the requested school
        if learner.school_id.to_s != school.id.to_s
          Rails.logger.warn "⚠️ [InvitationService] Learner belongs to different school!"
          Rails.logger.warn "   Learner school: #{learner.school_id}"
          Rails.logger.warn "   Request school: #{school.id}"
        end
      end

      # 3. Create the invitation
      invitation_data = {
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school: school,
        role: @role,
        token: generate_token,
        learner_number: @learner_number,
        parent_name: @parent_name,
        grade_id: @grade_id,
        invited_via: @invited_via
      }
      
      # Add learner info if found
      if learner
        invitation_data[:learner_ids] = [learner.id.to_s]
        invitation_data[:learner_names] = [learner.full_name]
      else
        invitation_data[:learner_ids] = []
        invitation_data[:learner_names] = []
      end

      invitation = Invitation.new(invitation_data)

      if invitation.save
        Rails.logger.info "✅ [InvitationService] Invitation created successfully!"
        Rails.logger.info "   ID: #{invitation.id}"
        Rails.logger.info "   Token: #{invitation.token}"
        Rails.logger.info "   Learner linked: #{learner.present?}"
        
        send_sms(invitation)
        invitation
      else
        Rails.logger.error "❌ [InvitationService] Failed to save invitation: #{invitation.errors.full_messages}"
        invitation
      end
      
    rescue => e
      Rails.logger.error "❌ [InvitationService] Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      invitation = Invitation.new
      invitation.errors.add(:base, e.message)
      invitation
    end

    private

    def find_school(school_id)
      Rails.logger.info "🔍 [InvitationService] Looking for school..."
      
      # Try direct find
      school = School.find_by(id: school_id)
      return school if school
      
      # Try BSON conversion
      if school_id.is_a?(String)
        begin
          bson_id = BSON::ObjectId.from_string(school_id)
          school = School.find_by(_id: bson_id)
          return school if school
        rescue BSON::ObjectId::Invalid
          # Not a valid BSON string
        end
      end
      
      nil
    end

    def find_learner_by_accession_number(learner_number)
      # Try different field names (your DB shows "accessionNumber" with capital N)
      learner = Learner.find_by(accessionNumber: learner_number)
      return learner if learner
      
      learner = Learner.find_by(accession_number: learner_number)
      return learner if learner
      
      # Try case-insensitive search
      learner = Learner.where(
        "$or" => [
          { accessionNumber: /#{Regexp.escape(learner_number)}/i },
          { accession_number: /#{Regexp.escape(learner_number)}/i }
        ]
      ).first
      
      learner
    end

    def generate_token
      loop do
        token = SecureRandom.hex(10)
        break token unless Invitation.where(token: token).exists?
      end
    end

    def send_sms(invitation)
      Rails.logger.info "📱 [InvitationService] SMS would be sent to #{invitation.recipient_phone_number}"
      Rails.logger.info "   Magic link: ?token=#{invitation.token}&school=#{invitation.school_id}"
      
      # TODO: Implement actual SMS/WhatsApp sending
      # For testing, just return true
      true
    end
  end
end