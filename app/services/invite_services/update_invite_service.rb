module InviteServices
  class UpdateInviteService
    def initialize(invite, params)
      @invite = invite
      @params = params
    end

    def call
      if @invite.update(@params)
        { success: true, invite: @invite }
      else
        { success: false, errors: @invite.errors.full_messages }
      end
    end
  end
end
