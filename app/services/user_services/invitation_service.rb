# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(sender:, recipient_phone_number:, school_id:, role:)
      @sender = sender
      @recipient_phone_number = recipient_phone_number
      @school_id = school_id
      @role = role
      
      Rails.logger.info "🔹 [InvitationService] Initialized with: sender=#{@sender&.id}, phone=#{@recipient_phone_number}, school_id=#{@school_id}, role=#{@role}"
    end

    def call
      Rails.logger.info "🔹 [InvitationService#call] Starting invitation process"
      
      begin
        # Step 1: Find the school
        school = find_school
        return school if school.is_a?(Invitation) && school.errors.any? # Return early if school not found

        # Step 2: Generate unique token
        token = generate_token
        Rails.logger.info "🔹 [InvitationService#call] Generated token: #{token[0..8]}..."

        # Step 3: Create invitation
        invitation = create_invitation(school, token)
        
        # Step 4: Send SMS if saved successfully
        if invitation.persisted?
          send_sms(invitation)
          Rails.logger.info "✅ [InvitationService#call] Invitation created successfully: ID=#{invitation.id}"
        else
          Rails.logger.error "❌ [InvitationService#call] Failed to save invitation: #{invitation.errors.full_messages}"
        end

        invitation

      rescue => e
        Rails.logger.error "💥 [InvitationService#call] Unexpected error: #{e.message}"
        Rails.logger.error "💥 [InvitationService#call] Backtrace: #{e.backtrace.first(10).join("\n")}"
        
        # Create a failed invitation with error
        invitation = Invitation.new
        invitation.errors.add(:base, "Internal server error: #{e.message}")
        invitation
      end
    end

    private

    def find_school
      Rails.logger.info "🔹 [InvitationService#find_school] Looking for school with ID: #{@school_id}"
      
      school = School.where(id: @school_id).first
      
      if school
        Rails.logger.info "✅ [InvitationService#find_school] School found: ID=#{school.id}, Name=#{school.name}"
        school
      else
        Rails.logger.error "❌ [InvitationService#find_school] School not found with ID: #{@school_id}"
        invitation = Invitation.new
        invitation.errors.add(:school, 'not found')
        invitation
      end
    rescue => e
      Rails.logger.error "💥 [InvitationService#find_school] Error finding school: #{e.message}"
      invitation = Invitation.new
      invitation.errors.add(:school, "error looking up: #{e.message}")
      invitation
    end

    def generate_token
      Rails.logger.info "🔹 [InvitationService#generate_token] Generating unique token"
      
      max_attempts = 5
      attempts = 0
      
      loop do
        attempts += 1
        token = SecureRandom.hex(10)
        
        if attempts > max_attempts
          Rails.logger.error "💥 [InvitationService#generate_token] Failed to generate unique token after #{max_attempts} attempts"
          raise "Could not generate unique token after #{max_attempts} attempts"
        end
        
        token_exists = Invitation.where(token: token).exists?
        
        if token_exists
          Rails.logger.warn "⚠️ [InvitationService#generate_token] Token collision detected, generating new token (attempt #{attempts})"
        else
          Rails.logger.info "✅ [InvitationService#generate_token] Unique token generated successfully (attempt #{attempts})"
          return token
        end
      end
    rescue => e
      Rails.logger.error "💥 [InvitationService#generate_token] Error generating token: #{e.message}"
      raise
    end

    def create_invitation(school, token)
      Rails.logger.info "🔹 [InvitationService#create_invitation] Creating invitation record"
      
      invitation = Invitation.new(
        sender: @sender,
        recipient_phone_number: @recipient_phone_number,
        school: school,
        role: @role,
        token: token
      )

      Rails.logger.info "🔹 [InvitationService#create_invitation] Invitation attributes: #{invitation.attributes.except('token')}"

      if invitation.save
        Rails.logger.info "✅ [InvitationService#create_invitation] Invitation saved successfully: ID=#{invitation.id}"
      else
        Rails.logger.error "❌ [InvitationService#create_invitation] Validation errors: #{invitation.errors.full_messages}"
        Rails.logger.error "❌ [InvitationService#create_invitation] Invalid attributes: #{invitation.attributes.inspect}"
      end

      invitation
    rescue => e
      Rails.logger.error "💥 [InvitationService#create_invitation] Error saving invitation: #{e.message}"
      Rails.logger.error "💥 [InvitationService#create_invitation] Backtrace: #{e.backtrace.first(5).join("\n")}"
      
      invitation = Invitation.new
      invitation.errors.add(:base, "Failed to create invitation: #{e.message}")
      invitation
    end

    def send_sms(invitation)
      Rails.logger.info "🔹 [InvitationService#send_sms] Preparing to send SMS"
      
      # In a real application, you would integrate with an SMS gateway like Twilio.
      # For this example, we'll just log the message.
      message = "Sending SMS to #{invitation.recipient_phone_number}: You have been invited to join our school. Please click this link to register: [invitation_link]"
      
      Rails.logger.info "📱 [InvitationService#send_sms] #{message}"
      
      # Simulate SMS sending (replace with actual SMS service integration)
      # TwilioService.new.send_sms(
      #   to: invitation.recipient_phone_number,
      #   body: "You have been invited to join #{invitation.school.name}. Use this link to register: https://yourapp.com/join?token=#{invitation.token}"
      # )
      
      Rails.logger.info "✅ [InvitationService#send_sms] SMS sent successfully (simulated)"
    rescue => e
      Rails.logger.error "💥 [InvitationService#send_sms] Error sending SMS: #{e.message}"
      # Don't fail the whole invitation process if SMS fails
    end
  end
end