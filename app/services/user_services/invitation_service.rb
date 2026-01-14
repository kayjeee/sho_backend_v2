# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    ServiceResult = Struct.new(:success, :errors, :invitation, keyword_init: true)
    
    def initialize(params)
      @params = params.symbolize_keys
      @errors = []
      
      # Extract parameters with defaults
      @sender = @params[:sender]
      @recipient_phone_number = @params[:phone_number] || @params[:recipient_phone_number]
      @school_id = @params[:school_id].to_s
      @learner_numbers = @params[:learner_numbers] || Array(@params[:learner_number]).compact
      @role = @params[:role] || 'parent'
      @parent_name = @params[:parent_name]
      @grade_id = @params[:grade_id]
      @invited_via = @params[:invited_via] || 'whatsapp'
      @country_code = @params[:country_code]
      @country_name = @params[:country_name]
      
      Rails.logger.info "🔧 InvitationService initialized:"
      Rails.logger.info "   Phone: #{@recipient_phone_number}"
      Rails.logger.info "   School: #{@school_id}"
      Rails.logger.info "   Learner numbers: #{@learner_numbers}"
      Rails.logger.info "   Role: #{@role}"
    end
    
    def call
      validate!
      
      if @errors.any?
        Rails.logger.error "❌ Validation failed: #{@errors}"
        return ServiceResult.new(success: false, errors: @errors)
      end
      
      invitation = create_invitation
      Rails.logger.info "✅ Invitation created successfully: #{invitation.id}"
      
      ServiceResult.new(success: true, invitation: invitation)
    rescue => e
      Rails.logger.error "❌ InvitationService error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      ServiceResult.new(success: false, errors: [e.message])
    end
    
    private
    
    def create_invitation
      klass = @role == 'parent' ? LearnerInvitation : TeacherInvitation
      
      Rails.logger.info "📝 Creating #{klass.name} with attributes: #{invitation_attributes}"
      
      klass.create!(invitation_attributes)
    end
    
    def invitation_attributes
      {
        sender_id: @sender&.id,
        recipient_phone_number: @recipient_phone_number,
        phone_number: @recipient_phone_number,
        school_id: @school_id,
        learner_numbers: @learner_numbers,
        learner_number: @learner_numbers.first,
        role: @role,
        parent_name: @parent_name,
        grade_id: @grade_id,
        invited_via: @invited_via,
        country_code: @country_code,
        country_name: @country_name,
        status: 'pending',
        token: generate_token
      }.compact
    end
    
    def generate_token
      loop do
        token = SecureRandom.urlsafe_base64(32)
        break token unless Invitation.where(token: token).exists?
      end
    end
    
    def validate!
      @errors << "Phone number missing" if @recipient_phone_number.blank?
      @errors << "School missing" if @school_id.blank?
      @errors << "Learner number missing" if @learner_numbers.blank?
      @errors << "Invalid role: #{@role}" unless %w[parent teacher].include?(@role)
    end
  end
end