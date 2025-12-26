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
    end

    def call
      Rails.logger.info "🔹 [InvitationService] Creating invitation for learner #{@learner_number} at school #{@school_id}"

      school = School.find(@school_id)
      learner = Learner.find_by(school_id: school.id, accession_number: @learner_number)

      unless learner
        Rails.logger.error "❌ [InvitationService] Learner not found with number: #{@learner_number}"
        invitation = Invitation.new
        invitation.errors.add(:learner, 'not found')
        return invitation
      end

      invitation = Invitation.create!(
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school: school,
        role: @role,
        token: generate_token,
        learner_number: @learner_number,
        learner_ids: [learner.id.to_s],
        learner_names: [learner.full_name],
        parent_name: @parent_name,
        grade_id: @grade_id,
        invited_via: @invited_via
      )

      Rails.logger.info "✅ [InvitationService] Invitation created: #{invitation.id} with token: #{invitation.token}"
      
      send_sms(invitation)
      invitation

    rescue Mongoid::Errors::DocumentNotFound => e
      Rails.logger.error "❌ [InvitationService] School not found: #{@school_id}"
      invitation = Invitation.new
      invitation.errors.add(:school, 'not found')
      invitation
    rescue => e
      Rails.logger.error "❌ [InvitationService] Error: #{e.message}"
      invitation = Invitation.new
      invitation.errors.add(:base, e.message)
      invitation
    end

    private

    def find_learners(school)
      if @learner_ids.any?
        return Learner.where(school_id: school.id, :id.in => @learner_ids)
      end

      Learner.where(school_id: school.id).or(
        { 'parent_info.phone' => @recipient_phone_number },
        { 'parent_info.contact_number' => @recipient_phone_number },
        { 'parent_info.primary_contact' => @recipient_phone_number }
      )
    end

    def generate_token
      loop do
        token = SecureRandom.hex(10)
        break token unless Invitation.where(token: token).exists?
      end
    end

    def send_sms(invitation)
      Rails.logger.info "📱 [InvitationService] Sending SMS to #{invitation.recipient_phone_number} with token: #{invitation.token}"
      # Your SMS logic here
    end
  end
end
