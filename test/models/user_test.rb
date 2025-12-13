# test/models/user_test.rb
require 'test_helper'

class UserTest < ActiveSupport::TestCase
  setup do
    @user_with_invitation = users(:parent_one)
    @user_without_invitation = users(:parent_two)
    @invitation = invitations(:one)
  end

  test 'onboarding_prefill should return invitation data if an invitation exists' do
    # Ensure the invitation is associated with the user
    @invitation.update(user_id: @user_with_invitation.id)

    prefill_data = @user_with_invitation.onboarding_prefill

    assert_not_empty prefill_data
    assert_equal @invitation.recipient_phone_number, prefill_data[:phone_number]
    assert_equal @invitation.school_id, prefill_data[:school_id]
  end

  test 'onboarding_prefill should return an empty hash if no invitation exists' do
    # Ensure no invitation is associated with this user
    Invitation.where(user_id: @user_without_invitation.id).delete_all

    prefill_data = @user_without_invitation.onboarding_prefill

    assert_empty prefill_data
  end

  test 'onboarding_prefill should handle DocumentNotFound error gracefully' do
    # This user has no invitation, ensuring find_by would raise an error
    prefill_data = users(:parent_two).onboarding_prefill
    assert_equal({}, prefill_data, "Expected empty hash when no invitation is found")
  end
end
