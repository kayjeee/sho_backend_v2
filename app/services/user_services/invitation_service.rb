# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(sender:, recipient_phone_number:, school_id:, role:)
      @sender = sender
      @recipient_phone_number = recipient_phone_number
      @school_id = school_id
      @role = role
    end

    def call
      school = School.where(id: @school_id).first
      unless school
        invitation = Invitation.new
        invitation.errors.add(:school, 'not found')
        return invitation
      end

      invitation = Invitation.new(
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school: school,
        role: @role,
        token: generate_token
      )

      if invitation.save
        send_sms(invitation)
      end

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
      # In a real application, you would integrate with an SMS gateway like Twilio.
      # For this example, we'll just log the message.
      Rails.logger.info "Sending SMS to #{invitation.recipient_phone_number}: You have been invited to join our school. Please click this link to register: [invitation_link]"
    end
  end
end
