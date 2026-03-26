# app/services/user_services/verify_invitation_service.rb
module UserServices
  class VerifyInvitationService
    def initialize(token:, auth0_id:)
      @token = token
      @auth0_id = auth0_id
    end

    def call
      invitation = find_invitation
      return { success: false, message: "Invitation not found or already processed" } unless invitation

      user = User.find_or_initialize_by(auth0_id: @auth0_id)

      # 1. Update user attributes and atomic fields
      update_user_attributes(user, invitation)

      # 2. Always save the User record
      if user.changed? || user.new_record?
        user.save!
        Rails.logger.info "📝 User profile updated/created for #{@auth0_id}"
      end

      # 3. CRUCIAL: Mark invitation as accepted BEFORE calling role-specific services
      # This prevents recursive loops if the role-specific service re-verifies.
      invitation.update!(
        status: 'accepted',
        accepted_at: Time.current
      )

      # 4. Handle Role-Specific logic
      if invitation.is_a?(TeacherInvitation) || (invitation.respond_to?(:role) && invitation.role == 'teacher')
        # Call non-recursive completion method
        teacher = TeacherServices::TeacherInvitationService.complete_teacher_onboarding(invitation, user)
      else
        # Find learners (parent flow)
        learners = find_invitation_learners(invitation)
        link_parent_to_learners(learners, user)
      end

      # 5. Determine centralized redirect path
      user.reload
      redirect_path = if user.roles.include?('teacher')
                        if user.onboarding_completed
                          # Use specific dashboard path if teacher record was found/created
                          if teacher && invitation.respond_to?(:school_slug)
                            "/teacher/school/#{invitation.school_slug}/teachers/#{teacher.slug}/dashboard"
                          else
                            "/teacher/dashboard"
                          end
                        else
                          "/teacher/onboarding"
                        end
                      else
                        user.onboarding_completed ? "/dashboard" : "/parent/onboarding"
                      end

      {
        success: true,
        user: user,
        invitation: invitation,
        learners: learners || [],
        redirect_path: redirect_path
      }
    rescue => e
      Rails.logger.error "❌ VerifyInvitationService Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      { success: false, message: e.message }
    end

    private

    def find_invitation
      # Searching across specific collections as seen in logs
      Invitation.where(token: @token, status: 'pending').first ||
      LearnerInvitation.where(token: @token, status: 'pending').first ||
      TeacherInvitation.find_by_token(@token)&.then { |ti| ti.status == 'pending' ? ti : nil }
    end

    def update_user_attributes(user, invitation)
      # Use |= for array roles and school_ids to prevent duplicates
      user.school_ids ||= []
      user.school_ids |= [invitation.school_id.to_s]

      # Role logic: Add the role from the invitation
      if invitation.respond_to?(:role) && invitation.role.present?
        user.roles ||= []
        user.roles |= [invitation.role.to_s.downcase]
      end

      # Atomic updates using MongoDB operators ($addToSet) to prevent duplicates in DB
      user.add_to_set(school_ids: invitation.school_id.to_s)
      user.add_to_set(roles: invitation.role.to_s.downcase) if invitation.respond_to?(:role) && invitation.role.present?

      # Update contact info if blank
      user.phone_number ||= invitation.recipient_phone_number if invitation.respond_to?(:recipient_phone_number)
      user.invited_via ||= invitation.invited_via if invitation.respond_to?(:invited_via)
      user.accepted_at ||= Time.current

      # Placeholder info if user is new
      if user.new_record?
        user.email ||= "#{invitation.recipient_phone_number}@placeholder.com" if invitation.respond_to?(:recipient_phone_number)
        user.name ||= (invitation.respond_to?(:teacher_name) ? invitation.teacher_name : invitation.respond_to?(:parent_name) ? invitation.parent_name : "User")
      end

      # 🍎 TEACHER SPECIFIC METADATA
      # The dashboard requires teachers to be searchable by slug/auth0_id
      if user.roles.include?('teacher')
        user.status = 'active' if user.status.blank?
      end

      # For parents, also set status
      if user.roles.include?('parent')
        user.status = 'active' if user.status.blank?
      end
    end

    def find_invitation_learners(invitation)
      return [] if invitation.is_a?(TeacherInvitation)

      # Logic from original controller
      if invitation.respond_to?(:learner_ids) && invitation.learner_ids.present?
        learners = Learner.where(:id.in => invitation.learner_ids).to_a
        return learners if learners.present?
      end

      numbers = extract_learner_numbers(invitation)
      if numbers.any?
        learners = Learner.where(school_id: invitation.school_id.to_s, :accession_number.in => numbers).to_a
        return learners if learners.present?
      end

      []
    end

    def extract_learner_numbers(invitation)
      numbers = []
      numbers += Array(invitation.learner_numbers) if invitation.respond_to?(:learner_numbers)
      numbers << invitation.learner_number if invitation.respond_to?(:learner_number)
      numbers.compact.uniq
    end

    def link_teacher_to_grades(invitation, user)
      # Handled by TeacherInvitationService
    end

    def link_parent_to_learners(learners, user)
      learners.each do |learner|
        learner.add_parent(user.auth0_id)
      end

      if learners.any?
        UserSchoolRole.find_or_create_by!(
          user: user,
          school_id: learners.first.school_id,
          role: 'parent'
        ) do |role|
          role.status = 0
        end
      end
    end
  end
end
