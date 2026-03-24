# app/services/teacher_services/teacher_invitation_service.rb
module TeacherServices
  class TeacherInvitationService
    def self.accept_invitation(token, auth0_id)
      # 1. Find the TeacherInvitation by token
      invitation = TeacherInvitation.find_by_token(token)
      return { success: false, message: "Invitation not found or already processed" } unless invitation && invitation.status == 'pending'

      # 2. Find or initialize the User by auth0_id
      user = User.find_or_initialize_by(auth0_id: auth0_id)

      # 3. Find or create Teacher record
      # Ensuring the Teacher record matches this auth0_id and the invitation's school_id
      teacher = Teacher.find_or_create_by!(auth0_id: auth0_id, school_id: invitation.school_id) do |t|
        t.user = user
        t.name = invitation.teacher_name
        t.email = user.email || "#{invitation.recipient_phone_number}@placeholder.com"
        t.status = 'active'
      end

      # Consistency: Ensure the Teacher document status is set to active.
      teacher.update!(status: 'active') unless teacher.status == 'active'

      # 4. Atomic Updates for User document using MongoDB operators ($addToSet)
      # Use $addToSet to prevent duplicates in roles and school_ids arrays
      user.add_to_set(roles: 'teacher')
      user.add_to_set(school_ids: invitation.school_id.to_s)

      # 5. Onboarding Logic
      # Set onboarding_completed to false if they haven't completed the teacher-specific steps.
      # For now, we set it to false if it's not already true.
      user.set(onboarding_completed: false) unless user.onboarding_completed == true

      # 6. Mark invitation as accepted
      invitation.update!(status: 'accepted', accepted_at: Time.current)

      # 7. Link Grades (Assignments)
      link_grades(invitation, user, teacher)

      # 8. Determine redirect path
      user.reload
      # Points to /teacher/onboarding if profile is incomplete, or dashboard if complete.
      redirect_path = user.onboarding_completed ?
        "/teacher/school/#{invitation.school_slug}/teachers/#{teacher.slug}/dashboard" :
        "/teacher/onboarding"

      {
        success: true,
        user: user,
        teacher: teacher,
        invitation: invitation,
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
          teacher: user,
          grade_id: gid,
          school_id: invitation.school_id,
          role_type: 'primary',
          assigned_by: invitation.sender || user,
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
