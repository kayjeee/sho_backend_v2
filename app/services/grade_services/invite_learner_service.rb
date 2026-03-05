module GradeServices
  class InviteLearnerService
    attr_reader :grade, :user, :invitation_params, :errors

    ServiceResult = Struct.new(:success, :errors, :invitation, keyword_init: true)

    def initialize(grade:, invitation_params:, user: nil)
      @grade             = grade
      @user              = user
      @invitation_params = invitation_params
      @errors            = []
    end

    def call
      validate_permissions unless user.nil?
      return ServiceResult.new(success: false, errors: errors) if errors.any?

      validate_invitation_constraints
      return ServiceResult.new(success: false, errors: errors) if errors.any?

      create_invitation
    end

    private

    def validate_permissions
      unless can_invite_learner?
        errors << "You don't have permission to invite learners to this grade"
      end
    end

    def can_invite_learner?
      return true if user.roles.include?('Admin')

      UserSchoolRole.where(
        user:   user,
        school: grade.school,
        role:   ['Admin', 'Teacher'],
        status: 0
      ).exists?
    end

    def validate_invitation_constraints
      unless grade.can_enroll_learner?
        errors << "Grade is not accepting new learners (inactive or at capacity)"
      end

      # Check for duplicate pending invitation by phone number
      if invitation_params[:recipient_phone_number].present?
        existing = LearnerInvitation.where(
          status:                 'pending',
          grade_id:               grade.id.to_s,
          recipient_phone_number: invitation_params[:recipient_phone_number]
        ).first

        errors << "An invitation is already pending for this phone number" if existing
      end
    end

    def create_invitation
      invitation = LearnerInvitation.new(
        grade:     grade,
        grade_id:  grade.id.to_s,
        school_id: grade.school_id.to_s,
        sender:    user,
        **invitation_params
      )

      if invitation.save
        Rails.logger.info "✅ Learner invitation created: #{invitation.recipient_phone_number} for grade #{grade.name}"
        ServiceResult.new(success: true, invitation: invitation)
      else
        Rails.logger.error "❌ Failed to create learner invitation: #{invitation.errors.full_messages.join(', ')}"
        ServiceResult.new(success: false, errors: invitation.errors.full_messages)
      end
    rescue => e
      Rails.logger.error "❌ Error in InviteLearnerService: #{e.message}"
      ServiceResult.new(success: false, errors: [e.message])
    end
  end
end