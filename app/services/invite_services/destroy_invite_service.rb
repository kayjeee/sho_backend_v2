module InviteServices
  class DestroyInviteService
    def initialize(invite)
      @invite = invite
    end

    def call
      if @invite.destroy
        { success: true }
      else
        { success: false, errors: @invite.errors.full_messages }
      end
    end
  end
end
