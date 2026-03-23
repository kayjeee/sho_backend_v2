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

      # Update user attributes from invitation
      update_user_attributes(user, invitation)

      # FIX: Using .changed? instead of the buggy .changes_to_save
      if user.changed?
        user.save!
        Rails.logger.info "📝 Updated user #{@auth0_id} during invitation verification"
      end

      # Find learners associated with invitation
      learners = find_invitation_learners(invitation)

      # Process invitation acceptance based on type
      if invitation.is_a?(TeacherInvitation) || (invitation.respond_to?(:role) && invitation.role == 'teacher')
        link_teacher_to_grades(invitation, user)
      else
        link_parent_to_learners(learners, user)
      end

      # Mark invitation as accepted
      invitation.update!(
        status: 'accepted',
        accepted_at: Time.current
      )

      {
        success: true,
        user: user,
        invitation: invitation,
        learners: learners
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
      user.school_ids ||= []
      user.school_ids |= [invitation.school_id.to_s]

      # Role logic: Add the role from the invitation
      if invitation.respond_to?(:role) && invitation.role.present?
        user.roles ||= []
        user.roles |= [invitation.role.to_s.downcase]
      end

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
      # Create or update the Teacher record
      teacher = Teacher.find_or_create_by!(auth0_id: user.auth0_id, school_id: invitation.school_id) do |t|
        t.name = invitation.respond_to?(:teacher_name) ? invitation.teacher_name : user.name
        t.email = user.email
        t.slug = t.name.to_s.parameterize
        t.status = 'active'
      end

      grade_ids = invitation.respond_to?(:grade_ids) ? (invitation.grade_ids.presence || [invitation.grade_id].compact) : [invitation.grade_id].compact

      grade_ids.each do |gid|
        TeacherGradeAssignment.find_or_create_by!(
          teacher: user,
          grade_id: gid,
          school_id: invitation.school_id,
          role_type: 'primary',
          assigned_by: invitation.respond_to?(:sender) ? (invitation.sender || user) : user,
          status: 0
        ) do |tga|
          tga.teacher_model_id = teacher.id
        end
      end

      UserSchoolRole.find_or_create_by!(
        user: user,
        school_id: invitation.school_id,
        role: 'teacher'
      ) do |role|
        role.status = 0
      end
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
