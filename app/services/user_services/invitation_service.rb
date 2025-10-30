# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(sender:, recipient_phone_number:, school_id:)
      @sender = sender
      @recipient_phone_number = recipient_phone_number
      @school_id = school_id
    end

    def call
      invitation = Invitation.create!(
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school_id: @school_id,
        token: generate_token
      )
      send_sms(invitation)
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
