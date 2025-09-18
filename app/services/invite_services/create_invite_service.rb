# app/services/invite_services/create_invite_service.rb
module InviteServices
  class CreateInviteService
    def initialize(params, current_user = nil)
      @params = params
      @current_user = current_user
    end

    def call
      school = School.find_by(id: @params[:school_id])
      return { success: false, errors: ['School not found'] } unless school

      # Generate a unique PR code
      pr_code = generate_pr_code(school)

      # Create the invite - handle nil user
      invite_attributes = @params.merge(
        pr_code: pr_code,
        status: 'pending'
      )
      
      # Only add user if it exists
      invite_attributes[:user] = @current_user if @current_user

      invite = Invite.new(invite_attributes)

      if invite.save
        # Generate invite link
        invite.update(invite_link: generate_invite_link(invite))

        # TODO: Generate QR code
        # TODO: Send notifications

        { success: true, invite: invite }
      else
        { success: false, errors: invite.errors.full_messages }
      end
    end

    private

    def generate_invite_link(invite)
      "https://your-frontend-url.com/invites/accept?token=#{invite.pr_code}"
    end

    def generate_pr_code(school)
      school_prefix = school.schoolName.first(4).upcase
      recipient_type_prefix = @params[:recipient_type]&.first(3)&.upcase || "INV"
      random_part = SecureRandom.hex(3).upcase
      "#{school_prefix}-#{recipient_type_prefix}-#{random_part}"
    end
  end
end