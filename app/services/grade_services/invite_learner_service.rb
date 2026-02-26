module GradeServices
  class InviteLearnerService
    attr_reader :grade, :user, :invitation_params, :errors

    ServiceResult = Struct.new(:success, :errors, :invitation, keyword_init: true)

    def initialize(grade:, invitation_params:, user: nil)
      @grade = grade
      @user = user
      @invitation_params = invitation_params
      @errors = []
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
        user: user,
        school: grade.school,
        role: ['Admin', 'Teacher'],
        status: 0
      ).exists?
    end

    def validate_invitation_constraints
      unless grade.can_enroll_learner?
        errors << "Grade is not accepting new learners (inactive or at capacity)"
      end

      if invitation_params[:learner_email].present?
        existing_email_invitation = LearnerInvitation.pending.where(
          grade: grade,
          learner_email: invitation_params[:learner_email]
        ).first

        errors << "An invitation is already pending for this email address" if existing_email_invitation
      end

      if invitation_params[:learner_phone].present?
        existing_phone_invitation = LearnerInvitation.pending.where(
          grade: grade,
          learner_phone: invitation_params[:learner_phone]
        ).first

        errors << "An invitation is already pending for this phone number" if existing_phone_invitation
      end
    end

    def create_invitation
      invitation = LearnerInvitation.new(
        grade: grade,
        school_id: grade.school_id.to_s,
          school_name_cache: grade.school&.schoolName || grade.school&.name,
        sender: user,
        **invitation_params
      )

      if invitation.save
        Rails.logger.info "✅ Learner invitation created: #{invitation.recipient_phone_number} for grade #{grade.name}"
        # TODO: Implement actual sending of invitation (email/SMS) as needed
        # InvitationMailer.learner_invitation(invitation).deliver_later

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
