# app/services/teacher_services/teacher_invitation_service.rb
module TeacherServices
  class TeacherInvitationService
    def self.accept_invitation(token, auth0_id)
      # 1. Find the TeacherInvitation by token and ensure it is pending.
      invitation = TeacherInvitation.find_by_token(token)
      return { success: false, message: "Invitation not found or already processed" } unless invitation && invitation.status == 'pending'

      # 2. Find or initialize the User by auth0_id.
      user = User.find_or_initialize_by(auth0_id: auth0_id)

      # Use |= for array roles to prevent duplicates in memory
      user.roles ||= []
      user.roles |= ['teacher']

      # 4. Atomic Updates: Add "teacher" to the roles array and school_id to school_ids.
      # Use MongoDB atomic operators like $addToSet to prevent duplicate IDs.
      user.add_to_set(roles: 'teacher')
      user.add_to_set(school_ids: invitation.school_id.to_s)

      # Set onboarding_completed to false if they haven't completed the teacher-specific steps.
      if user.onboarding_completed.nil? || user.onboarding_completed == false
        user.onboarding_completed = false
      end

      user.save! if user.changed?

      # 3. CRUCIAL STEP: Finds the existing Teacher record (matching by auth0_id OR
      # matching the school_id and recipient_phone_number from the invitation)
      # and updates it with user_id and auth0_id.
      teacher = Teacher.where(auth0_id: auth0_id).first ||
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
          auth0_id: auth0_id,
          status: 'active'
        )
      else
        # Fallback to create if not found
        teacher = Teacher.find_or_create_by!(auth0_id: auth0_id, school_id: invitation.school_id) do |t|
          t.user_id = user.id
          t.name = invitation.teacher_name
          t.email = user.email || "#{invitation.recipient_phone_number}@placeholder.com"
          t.status = 'active'
          t.recipient_phone_number = invitation.recipient_phone_number
        end
      end

      # Consistency: Ensure the Teacher document status is set to active.
      teacher.set(status: 'active') unless teacher.status == 'active'

      # 4. Mark invitation as accepted.
      invitation.update!(status: 'accepted', accepted_at: Time.current)

      # 5. Create TeacherGradeAssignment records for all grade_ids found in the invitation.
      link_grades(invitation, user, teacher)

      # 6. Determine redirect path.
      user.reload
      # Points to /teacher/onboarding if the profile is incomplete, or the dashboard if complete.
      redirect_path = user.onboarding_completed ? "/teacher/dashboard" : "/teacher/onboarding"

      {
        success: true,
        user: user,
        redirect_path: redirect_path
      }
    rescue => e
      Rails.logger.error "❌ TeacherInvitationService Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, message: e.message }
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
