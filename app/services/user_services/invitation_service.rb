# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(sender:, recipient_phone_number:, school_id:, role: 'parent')
      @sender = sender
      @recipient_phone_number = recipient_phone_number
      @school_id = school_id
      @role = role
    end

    def call
      Rails.logger.info "🔹 [InvitationService] Creating invitation for #{@recipient_phone_number}"
      
      # Find school first
      school = School.find(@school_id)
      
      invitation = Invitation.create!(
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school: school,
        role: @role, # Add role to invitation
        token: generate_token
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