# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(sender:, recipient_phone_number:, school_id:, role: 'parent', learner_ids: [], parent_name: nil, grade_id: nil)
      @sender = sender
      @recipient_phone_number = recipient_phone_number
      @school_id = school_id
      @role = role
      @learner_ids = learner_ids
      @parent_name = parent_name
      @grade_id = grade_id
    end

    def call
      Rails.logger.info "🔹 [InvitationService] Creating invitation for #{@recipient_phone_number}"

      school = School.find(@school_id)
      learners = find_learners(school)
      learner_ids = learners.map { |learner| learner.id.to_s }
      learner_names = learners.map(&:full_name)

      invitation = Invitation.create!(
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school: school,
        role: @role,
        token: generate_token,
        learner_ids: learner_ids,
        learner_names: learner_names,
        parent_name: @parent_name,
        grade_id: @grade_id
      )

      Rails.logger.info "✅ [InvitationService] Invitation created: #{invitation.id} with token: #{invitation.token}"
      
      send_sms(invitation)
      invitation # Return the invitation object with token
      
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
      if @learner_ids&.any?
        return school.learners.where(:id.in => @learner_ids)
      end

      school.learners.or(
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