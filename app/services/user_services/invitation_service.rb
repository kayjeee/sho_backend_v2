# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    attr_reader :params, :result

    def initialize(params)
      @params = params
      @result = OpenStruct.new(success: false, errors: [], invitation: nil)
    end

    def call
      validate_params
      return result unless result.errors.empty?

      create_invitation
      result
    rescue => e
      result.errors << e.message
      result
    end

    private

    def validate_params
      result.errors << "Phone number is required" if params[:phone_number].blank?
      result.errors << "School ID is required" if params[:school_id].blank?
      result.errors << "Sender is required" if params[:sender].blank?
    end

    def create_invitation
      # Use the new Invitation model
      invitation = Invitation.new(
        recipient_phone_number: params[:phone_number],
        school_id: params[:school_id],
        grade_id: params[:grade_id],
        role: params[:role] || 'parent',
        invited_via: params[:invited_via] || 'whatsapp',
        parent_name: params[:parent_name],
        sender_id: params[:sender]&.id,
        status: 'pending',
        token: generate_token,
        expires_at: 7.days.from_now
      )

      if invitation.save
        result.success = true
        result.invitation = invitation
        # Send notification
        send_invitation_notification(invitation)
      else
        result.errors = invitation.errors.full_messages
      end
    end

    def generate_token
      loop do
        token = SecureRandom.hex(32)
        break token unless Invitation.exists?(token: token)
      end
    end

    def send_invitation_notification(invitation)
      # Implement your notification logic
      Rails.logger.info "📨 Sending invitation to #{invitation.recipient_phone_number} with token #{invitation.token}"
      
      # If you have WhatsApp service
      if defined?(WhatsappService)
        WhatsappService.send_invitation(invitation)
      end
    end
  end
end