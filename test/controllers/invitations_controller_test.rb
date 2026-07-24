require 'test_helper'
require 'cgi'

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Mongoid.purge!

    # Create School
    @school = School.create!(
      schoolName: "Test Secondary School",
      schoolEmail: "test@school.com"
    )

    # Create Grade
    @grade = Grade.create!(
      name: "Grade 9",
      level: 9,
      school: @school
    )

    # Create Learner
    @learner = Learner.create!(
      firstName: "John",
      lastName: "Doe",
      accessionNumber: "ACC123",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      status: 0, # active (Integer)
      gender: 0  # male (Integer)
    )

    # Create Parent User (the one accepting invitation)
    @parent = User.create!(
      name: "Parent User",
      email: "parent@test.com",
      auth0_id: "auth0|parent_test_user_unique",
      roles: ["guest"]
    )

    # Create Sender User (e.g. Admin or Teacher)
    @sender = User.create!(
      name: "Admin User",
      email: "admin@test.com",
      auth0_id: "auth0|admin_test_user_unique",
      roles: ["admin"]
    )
  end

  test "GET verify_with_details returns unified invitation info" do
    # Create Invitation
    invitation = Invitation.create!(
      token: "unique_test_token_details",
      recipient_phone_number: "27712345678",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      invited_via: "whatsapp",
      status: "pending",
      learner_ids: [@learner.id.to_s],
      learner_numbers: ["ACC123"],
      learner_names: ["John Doe"]
    )

    get "/invitations/#{invitation.token}/verify_with_details"
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal "unique_test_token_details", json_response['invitation']['token']
    assert_equal "Test Secondary School", json_response['invitation']['school_name']
    assert_equal "pending", json_response['invitation']['status']
  end

  test "POST bulk_create endpoint handles array payload and normalizes camelCase keys" do
    payload = {
      senderId: @sender.auth0_id,
      schoolId: @school.id.to_s,
      role: "parent",
      invitedVia: "whatsapp",
      invitations: [
        {
          phoneNumber: "27712345678",
          parentName: "Parent A",
          learnerNumber: "ACC123",
          gradeId: @grade.id.to_s,
          countryCode: "27",
          countryName: "South Africa"
        }
      ]
    }

    post "/api/v1/invitations/bulk_create", params: payload
    assert_response :created
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal 1, json_response['stats']['successful']
    assert_equal 0, json_response['stats']['failed']
    assert_not_nil json_response['invitations'].first['token']
  end

  test "POST verify (accept) transactionally links parent and completes onboarding link_learner step" do
    # Create Invitation
    invitation = Invitation.create!(
      token: "accept_test_token",
      recipient_phone_number: "27712345678",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_ids: [@learner.id.to_s],
      learner_numbers: ["ACC123"],
      learner_names: ["John Doe"]
    )

    payload = {
      token: "accept_test_token",
      auth0Id: @parent.auth0_id
    }

    # Accept the invitation
    post "/api/v1/invitations/verify", params: payload
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal "accepted", json_response['invitation']['status']

    # Reload database documents
    @learner.reload
    @parent.reload

    # Check parent-to-learner links
    assert_includes @learner.parent_ids, @parent.id

    # Check role and school sync
    assert_includes @parent.roles, "parent"
    assert_not_includes @parent.roles, "guest"
    assert_includes @parent.school_ids, @school.id

    # Check onboarding step link_learner auto-completion
    assert_includes @parent.onboarding_status.completed_steps, "link_learner"
  end

  test "GET show_by_path is fully functional on deprecated paths" do
    get "/api/v1/users/#{CGI.escape(@parent.auth0_id)}"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal "auth0|parent_test_user_unique", json_response['data']['user']['auth0_id']
  end

  test "GET schools_by_path is fully functional on deprecated paths" do
    # Associate school first
    @parent.school_ids << @school.id
    @parent.save!

    get "/api/v1/users/#{CGI.escape(@parent.auth0_id)}/schools"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal "Test Secondary School", json_response['data']['schools'].first['schoolName']
  end

  test "GET onboarding_status_by_path is fully functional on deprecated paths" do
    get "/api/v1/users/#{CGI.escape(@parent.auth0_id)}/onboarding_status"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal false, json_response['data']['onboardingCompleted']
  end
end
