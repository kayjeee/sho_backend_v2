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

      role_str = (params[:role] || 'parent').to_s.downcase
      if role_str == 'teacher'
        school_id_str = params[:school_id].to_s

        if params[:assigned_grade_ids].present?
          g_ids = Array(params[:assigned_grade_ids]).map(&:to_s).reject(&:blank?)
          g_bsons = g_ids.map { |id| BSON::ObjectId.legal?(id) ? BSON::ObjectId.from_string(id) : nil }.compact
          invalid_grades = Grade.where(:id.in => (g_ids + g_bsons).uniq).to_a.select { |g| g.school_id.to_s != school_id_str }
          if invalid_grades.any?
            result.errors << "Assigned grade does not belong to target school"
          end
        end

        if params[:subject_ids].present?
          s_ids = Array(params[:subject_ids]).map(&:to_s).reject(&:blank?)
          s_bsons = s_ids.map { |id| BSON::ObjectId.legal?(id) ? BSON::ObjectId.from_string(id) : nil }.compact
          invalid_subjects = Subject.where(:id.in => (s_ids + s_bsons).uniq).to_a.select { |s| s.school_id.to_s != school_id_str }
          if invalid_subjects.any?
            result.errors << "Subject does not belong to target school"
          end
        end
      end
    end

    def create_invitation
      invitation = Invitation.new(
        recipient_phone_number: params[:phone_number],
        school_id: params[:school_id],
        grade_id: params[:grade_id],
        role: params[:role] || 'parent',
        invited_via: params[:invited_via] || 'whatsapp',
        parent_name: params[:parent_name],
        assigned_grade_ids: Array(params[:assigned_grade_ids]).map(&:to_s),
        subject_ids: Array(params[:subject_ids]).map(&:to_s),
        teacher_type: params[:teacher_type] || 'staff',
        sender_id: params[:sender]&.id,
        status: 'pending',
        token: generate_token,
        expires_at: 7.days.from_now
      )

      if invitation.save
        result.success = true
        result.invitation = invitation
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
      Rails.logger.info "📨 Sending invitation to #{invitation.recipient_phone_number} with token #{invitation.token}"
      if defined?(WhatsappService)
        WhatsappService.send_invitation(invitation)
      end
    end
  end
end
