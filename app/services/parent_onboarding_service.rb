# app/services/parent_onboarding_service.rb
class ParentOnboardingService
  def self.call(invitation_token:, auth0_id:)
    new(invitation_token: invitation_token, auth0_id: auth0_id).call
  end

  attr_reader :invitation_token, :auth0_id

  def initialize(invitation_token:, auth0_id:)
    @invitation_token = invitation_token
    @auth0_id = auth0_id
  end

  def call
    invitation = Invitation.find_by(token: invitation_token, status: 'pending')
    return { success: false, error: 'Invitation not found or already used' } unless invitation

    user = User.find_by(auth0_id: auth0_id)
    return { success: false, error: 'User not found' } unless user

    learners = Learner.where(:_id.in => invitation.learner_ids)

    Mongoid::Clients.default.session do |session|
      session.with_transaction do
        update_user(user, invitation)
        link_learners(user, learners)
        update_invitation(invitation)
      end
    end

    { success: true, user: user, learners: learners }
  end

  private

  def update_user(user, invitation)
    user.phone_number = invitation.recipient_phone_number if user.phone_number.blank?
    user.invited_via = invitation.invited_via
    user.save!
  end

  def link_learners(user, learners)
    learners.add_to_set(parent_auth0_ids: user.auth0_id)
  end

  def update_invitation(invitation)
    invitation.update!(status: 'verified')
  end
end
