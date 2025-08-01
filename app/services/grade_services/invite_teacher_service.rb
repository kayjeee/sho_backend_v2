module GradeServices
  class InviteTeacherService
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
      unless can_invite_teacher?
        errors << "You don't have permission to invite teachers to this grade"
      end
    end

    def can_invite_teacher?
      return true if user.roles.include?('Admin')

      UserSchoolRole.where(
        user: user,
        school: grade.school,
        role: 'Admin',
        status: 0
      ).exists?
    end

    def validate_invitation_constraints
      if invitation_params[:teacher_email].present?
        existing = TeacherInvitation.pending.where(
          school: grade.school,
          teacher_email: invitation_params[:teacher_email]
        ).first

        errors << "An invitation is already pending for this teacher" if existing
      end

      if invitation_params[:teacher_email].present?
        existing_teacher = User.where(email: invitation_params[:teacher_email]).first
        if existing_teacher && existing_teacher.schools.include?(grade.school)
          errors << "This teacher is already associated with the school"
        end
      end

      assigned = invitation_params[:assigned_grades]
      if assigned.blank? || !assigned.is_a?(Array) || assigned.empty?
        errors << "At least one grade must be assigned"
      else
        validate_assigned_grades(assigned)
      end
    end

    def validate_assigned_grades(grade_ids)
      begin
        grade_object_ids = grade_ids.map { |id| BSON::ObjectId.from_string(id) }
      rescue BSON::ObjectId::Invalid => e
        errors << "One or more assigned grades have invalid IDs"
        return
      end

      valid_grades_count = grade.school.grades.where(:_id.in => grade_object_ids).count
      if valid_grades_count != grade_ids.size
        errors << "One or more assigned grades don't belong to this school"
      end
    end

    def create_invitation
      invitation = TeacherInvitation.new(
        school: grade.school,
        invited_by: user,
        assigned_grades: invitation_params[:assigned_grades] || [grade.id.to_s],
        teacher_email: invitation_params[:teacher_email],
        expires_at: invitation_params[:expires_at] || 14.days.from_now,
        invitation_data: invitation_params[:invitation_data] || {}
      )

      if invitation.save
        Rails.logger.info "✅ Teacher invitation created: #{invitation.teacher_email} for school #{grade.school.schoolName}"

        # Send invitation email asynchronously
        GradeMailer.teacher_invitation(invitation).deliver_later

        ServiceResult.new(success: true, invitation: invitation)
      else
        Rails.logger.error "❌ Failed to create teacher invitation: #{invitation.errors.full_messages.join(', ')}"
        ServiceResult.new(success: false, errors: invitation.errors.full_messages)
      end
    rescue => e
      Rails.logger.error "❌ Error in InviteTeacherService: #{e.message}"
      ServiceResult.new(success: false, errors: [e.message])
    end
  end
end
