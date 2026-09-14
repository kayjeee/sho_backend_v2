require "test_helper"

class LinkParentRoleInvitationTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Test School",
      schoolEmail: "test@school.org"
    )
    @sender = User.create!(
      name: "Admin User",
      email: "admin@school.org",
      auth0_id: "auth0|admin_parent_test"
    )
    @learner = Learner.create!(
      first_name: "Child",
      last_name: "User",
      accessionNumber: "ACC123",
      school_id: @school.id.to_s
    )
    @new_user = User.create!(
      name: "New Parent",
      email: "newparent@school.org",
      auth0_id: "auth0|new_parent_123",
      roles: ["guest"]
    )
  end

  test "accepting a parent invitation adds 'parent' to user's roles" do
    invitation = Invitation.create!(
      school_id: @school.id.to_s,
      sender: @sender,
      recipient_phone_number: "27829990000",
      role: "parent",
      learner_ids: [@learner.id.to_s]
    )

    post "/api/v1/invitations/verify", params: {
      token: invitation.token,
      auth0_id: @new_user.auth0_id
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]

    @new_user.reload
    assert_includes @new_user.roles, "parent"

    # Verify role_step_list resolves to PARENT_STEPS (8 steps)
    status = @new_user.onboarding_status
    assert_equal 8, status.total_steps_count
  end
end
