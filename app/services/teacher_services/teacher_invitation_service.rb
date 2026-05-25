# app/services/teacher_services/teacher_invitation_service.rb
module TeacherServices
  class TeacherInvitationService
    def self.accept_invitation(token, auth0_id)
      # This method is now legacy and should be refactored to use link_teacher_to_user
      # via VerifyInvitationService to prevent recursive loops.
      # For now, it delegates to VerifyInvitationService.
      UserServices::VerifyInvitationService.new(token: token, auth0_id: auth0_id).call
    end

    # Handle "Role-Specific" logic for Teachers
    def self.link_teacher_to_user(invitation, user)
      # 3. CRUCIAL STEP: Finds the existing Teacher record (matching by auth0_id OR
      # matching the school_id and recipient_phone_number from the invitation)
      # and updates it with user_id and auth0_id.
      teacher = Teacher.where(auth0_id: user.auth0_id).first ||
                Teacher.where(
                  school_id: invitation.school_id,
                  recipient_phone_number: invitation.recipient_phone_number
                ).first ||
                Teacher.where(
                  school_id: invitation.school_id,
                  email: user.email
                ).first

      if teacher
        teacher.update!(
          user_id: user.id,
          auth0_id: user.auth0_id,
          name: user.name.presence || user.display_name.presence || invitation.try(:teacher_name) || "Unknown Teacher",
          status: 'active'
        )
      else
        # Fallback to create if not found
        teacher = Teacher.find_or_create_by!(auth0_id: user.auth0_id, school_id: invitation.school_id) do |t|
          t.user_id = user.id
          t.name = user.name.presence || user.display_name.presence || invitation.try(:teacher_name) || "Unknown Teacher"
          t.email = user.email || "#{invitation.recipient_phone_number}@placeholder.com"
          t.status = 'active'
          t.recipient_phone_number = invitation.recipient_phone_number
        end
      end

      # Consistency: Ensure the Teacher document status is set to active.
      teacher.set(status: 'active') unless teacher.status == 'active'

      # Create TeacherGradeAssignment records for all grade_ids found in the invitation.
      link_grades(invitation, user, teacher)

      teacher
    end

    private

    def self.link_grades(invitation, user, teacher)
      grade_ids = invitation.respond_to?(:grade_ids) ? (invitation.grade_ids.presence || [invitation.grade_id].compact) : [invitation.grade_id].compact

      grade_ids.each do |gid|
        TeacherGradeAssignment.find_or_create_by!(
          teacher_id: user.id,
          grade_id: gid,
          school_id: invitation.school_id,
          role_type: 'primary',
          assigned_by: invitation.respond_to?(:sender) ? (invitation.sender || user) : user,
          status: 0
        ) do |tga|
          tga.teacher_model_id = teacher.id
        end
      end

      # Ensure UserSchoolRole exists
      UserSchoolRole.find_or_create_by!(
        user: user,
        school_id: invitation.school_id,
        role: 'teacher'
      ) do |role|
        role.status = 0
      end
    end
  end
end
