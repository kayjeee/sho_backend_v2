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
      gender: 0, # male (Integer)
      phone: "+27814296653",
      whatsapp: "+27814296653",
      telEmergency: "+27814296654"
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

  test "POST create (plain invitations endpoint) handles un-nested payload and maps sender key" do
    payload = {
      phone_number: "27814296653",
      school_id: @school.id.to_s,
      learner_numbers: ["56565"],
      role: "parent",
      parent_name: "kg",
      grade_id: @grade.id.to_s,
      invited_via: "whatsapp",
      sender: @sender.auth0_id,
      country_code: "27",
      country_name: "South Africa"
    }

    post "/api/v1/invitations", params: payload
    assert_response :created
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_not_nil json_response['invitation']['token']
    assert_equal "kg", json_response['invitation']['parent_name']
  end

  test "POST create on users endpoint handles flat (non-wrapped) JSON payload successfully" do
    payload = {
      name: "New Flat User",
      email: "flat_user@test.com",
      auth0_id: "auth0|flat_user_unique_123",
      roles: ["parent"]
    }

    post "/api/v1/users", params: payload
    assert_response :created
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal "New Flat User", json_response['data']['user']['name']
    assert_equal "flat_user@test.com", json_response['data']['user']['email']
  end

  test "GET onboarding_status with query string handles lookup successfully" do
    get "/api/v1/users/onboarding_status", params: { auth0_id: @parent.auth0_id }
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal false, json_response['data']['onboardingCompleted']
  end

  test "GET /api/v1/grades/:grade_id/learners returns accession_number, accessionNumber, and nested contact info" do
    get "/api/v1/grades/#{@grade.id}/learners"
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal 1, json_response['total']

    learner_json = json_response['learners'].first
    assert_equal "John Doe", "#{learner_json['firstName']} #{learner_json['lastName']}"
    assert_equal "ACC123", learner_json['accession_number']
    assert_equal "ACC123", learner_json['accessionNumber']

    # Check contact fields are present with correct nested structure
    assert_not_nil learner_json['contact']
    assert_equal "+27814296653", learner_json['contact']['phone']
    assert_equal "+27814296653", learner_json['contact']['whatsapp']
    assert_equal "+27814296654", learner_json['contact']['tel_emergency']
  end

  test "GET /api/v1/schools/:school_id/grades/:grade_id/learners returns learners successfully via nested route" do
    get "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/learners"
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal 1, json_response['total']
    assert_equal "John Doe", "#{json_response['learners'].first['first_name']} #{json_response['learners'].first['last_name']}"
  end

  test "GET nested grade learners returns 404 when grade belongs to a different school" do
    other_school = School.create!(
      schoolName: "Other High School",
      schoolEmail: "other@school.com"
    )

    get "/api/v1/schools/#{other_school.id}/grades/#{@grade.id}/learners"
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_equal "Grade not found", json_response['error']
  end

  test "GET /api/v1/invitations index returns invitations for school and supports status filtering" do
    # Clear and create two invitations with different statuses
    Invitation.delete_all
    inv1 = Invitation.create!(
      token: "index_test_token_1",
      recipient_phone_number: "27712345678",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "pending"
    )
    inv2 = Invitation.create!(
      token: "index_test_token_2",
      recipient_phone_number: "27712345679",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "cancelled"
    )

    # Fails without school_id
    get "/api/v1/invitations"
    assert_response :bad_request

    # Lists both for school_id
    get "/api/v1/invitations", params: { school_id: @school.id.to_s }
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 2, json_response['total']

    # Filter by pending
    get "/api/v1/invitations", params: { school_id: @school.id.to_s, status: "pending" }
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response['total']
    assert_equal "index_test_token_1", json_response['invitations'].first['token']

    # Filter by cancelled
    get "/api/v1/invitations", params: { school_id: @school.id.to_s, status: "cancelled" }
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response['total']
    assert_equal "index_test_token_2", json_response['invitations'].first['token']
  end

  test "POST /api/v1/invitations/:token/resend works successfully" do
    invitation = Invitation.create!(
      token: "resend_test_token",
      recipient_phone_number: "27712345678",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "cancelled"
    )

    post "/api/v1/invitations/#{invitation.token}/resend"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']

    # It generates a new token
    refute_equal "resend_test_token", json_response['invitation']['token']
    assert_equal "pending", json_response['invitation']['status']

    # Returns 404 for non-existent token
    post "/api/v1/invitations/invalid_token/resend"
    assert_response :not_found
  end

  test "POST /api/v1/invitations/:token/cancel works successfully" do
    invitation = Invitation.create!(
      token: "cancel_test_token",
      recipient_phone_number: "27712345678",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "pending"
    )

    post "/api/v1/invitations/#{invitation.token}/cancel"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal "cancelled", json_response['invitation']['status']
  end

  test "POST /api/v1/invitations/:token/admin_accept links and force-sets grade when matching parent exists" do
    another_grade = Grade.create!(
      name: "Grade 10",
      level: 10,
      school: @school
    )

    invitation = Invitation.create!(
      token: "admin_accept_test_token",
      recipient_phone_number: "27712345688",
      school_id: @school.id.to_s,
      grade_id: another_grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_ids: [@learner.id.to_s],
      learner_numbers: [@learner.accessionNumber],
      learner_names: [@learner.full_name]
    )

    # 1. No parent exists with that phone number yet -> 422
    post "/api/v1/invitations/#{invitation.token}/admin_accept"
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_match /No parent account found/, json_response['message']

    # 2. Create parent with matching phone number
    parent_user = User.create!(
      name: "Admin Accepted Parent",
      email: "admin_accept@test.com",
      auth0_id: "auth0|admin_accept_parent_unique",
      roles: ["guest"],
      phone_number: "27712345688"
    )

    # Now run admin_accept -> should succeed, link parent, mark accepted, and force-set learner's grade
    post "/api/v1/invitations/#{invitation.token}/admin_accept"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal "accepted", json_response['invitation']['status']

    # Verify parent linked to learner
    @learner.reload
    assert_includes @learner.parent_ids, parent_user.id

    # Verify learner grade force-set to another_grade in physical database
    raw_learner = Learner.collection.find(_id: @learner.id).first
    assert_equal another_grade.id.to_s, raw_learner['gradeId']
    assert_equal another_grade.id.to_s, @learner.grade_id
  end

  test "POST /api/v1/invitations/verify sets the learner's grade to the invitation's grade" do
    another_grade = Grade.create!(
      name: "Grade 11",
      level: 11,
      school: @school
    )

    inv_token = "verify_grade_test_token"
    invitation = Invitation.create!(
      token: inv_token,
      recipient_phone_number: "27712345699",
      school_id: @school.id.to_s,
      grade_id: another_grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_ids: [@learner.id.to_s],
      learner_numbers: [@learner.accessionNumber],
      learner_names: [@learner.full_name]
    )

    payload = {
      token: inv_token,
      auth0Id: @parent.auth0_id
    }

    post "/api/v1/invitations/verify", params: payload
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']

    # Reload and assert that learner grade has been updated in Mongo and the loaded model
    @learner.reload
    raw_learner = Learner.collection.find(_id: @learner.id).first
    assert_equal another_grade.id.to_s, raw_learner['gradeId']
    assert_equal another_grade.id.to_s, @learner.grade_id
  end

  test "POST /api/v1/invitations/match_by_phone returns 400 when missing parameters" do
    post "/api/v1/invitations/match_by_phone", params: { phone_number: "27620670152" }
    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_match /Missing required parameters/, json_response['message']
  end

  test "POST /api/v1/invitations/match_by_phone returns 404 when parent user doesn't exist" do
    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "27620670152",
      auth0_id: "auth0|non_existent_parent",
      school_id: @school.id.to_s
    }
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_match /No User found/, json_response['message']
  end

  test "POST /api/v1/invitations/match_by_phone successfully matches, links parent, and force-sets grade" do
    another_grade = Grade.create!(
      name: "Grade 12",
      level: 12,
      school: @school
    )

    # Create pending invitation with recipient_phone_number "0620670152" bypassing validation
    invitation = Invitation.new(
      token: "match_by_phone_single_token",
      recipient_phone_number: "0620670152",
      school_id: @school.id.to_s,
      grade_id: another_grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_ids: [@learner.id.to_s],
      learner_numbers: [@learner.accessionNumber],
      learner_names: [@learner.full_name]
    )
    invitation.save!(validate: false)

    # Call with a different country code and prefix representation "+27620670152"
    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "+27620670152",
      auth0_id: @parent.auth0_id,
      school_id: @school.id.to_s
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 1, json_response['matched_count']
    assert_equal "accepted", json_response['invitations'].first['status']

    # Verify parent linked to learner
    @learner.reload
    assert_includes @learner.parent_ids, @parent.id

    # Verify learner grade force-set in the database
    raw_learner = Learner.collection.find(_id: @learner.id).first
    assert_equal another_grade.id.to_s, raw_learner['gradeId']
    assert_equal another_grade.id.to_s, @learner.grade_id
  end

  test "POST /api/v1/invitations/match_by_phone successfully matches multiple children in one call" do
    another_grade = Grade.create!(
      name: "Grade 12",
      level: 12,
      school: @school
    )

    # Create a second learner for the school
    learner2 = Learner.create!(
      firstName: "Jane",
      lastName: "Doe",
      accessionNumber: "ACC456",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      status: 0,
      gender: 1
    )

    # Create 2 pending invitations for different learners but same phone "0620670152" bypassing validation
    inv1 = Invitation.new(
      token: "match_by_phone_multi_token_1",
      recipient_phone_number: "0620670152",
      school_id: @school.id.to_s,
      grade_id: another_grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_ids: [@learner.id.to_s],
      learner_numbers: [@learner.accessionNumber],
      learner_names: [@learner.full_name]
    )
    inv1.save!(validate: false)

    inv2 = Invitation.new(
      token: "match_by_phone_multi_token_2",
      recipient_phone_number: "0620670152",
      school_id: @school.id.to_s,
      grade_id: another_grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_ids: [learner2.id.to_s],
      learner_numbers: [learner2.accessionNumber],
      learner_names: [learner2.full_name]
    )
    inv2.save!(validate: false)

    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "27620670152",
      auth0_id: @parent.auth0_id,
      school_id: @school.id.to_s
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 2, json_response['matched_count']

    # Verify both invitations are accepted
    assert_equal "accepted", json_response['invitations'][0]['status']
    assert_equal "accepted", json_response['invitations'][1]['status']

    # Verify parent linked to both learners
    @learner.reload
    learner2.reload
    assert_includes @learner.parent_ids, @parent.id
    assert_includes learner2.parent_ids, @parent.id
  end

  test "POST /api/v1/invitations/match_by_phone returns success: true and matched_count: 0 when no match is found" do
    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "+27888888888",
      auth0_id: @parent.auth0_id,
      school_id: @school.id.to_s
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 0, json_response['matched_count']
    assert_empty json_response['invitations']
  end

  test "POST /api/v1/invitations/match_by_phone survives plain string school_id casting bug" do
    string_school_id = "6a767790a999fb1c3bfb1580"

    # Create learner with school_id as string
    learner = Learner.create!(
      firstName: "TestString",
      lastName: "Learner",
      accessionNumber: "STRACC999",
      school_id: string_school_id,
      grade_id: @grade.id.to_s,
      status: 0,
      gender: 0,
      phone: "+27814296653",
      telEmergency: "+27814296654"
    )

    # Create invitation with school_id as string and phone matching the learner
    invitation = Invitation.new(
      token: "string_school_id_test_token",
      recipient_phone_number: "27814296653",
      school_id: string_school_id,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_numbers: ["STRACC999"]
    )
    invitation.save!(validate: false)

    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "0814296653",
      auth0_id: @parent.auth0_id,
      school_id: string_school_id
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 1, json_response['matched_count']
    assert_equal "accepted", json_response['invitations'].first['status']

    # Verify parent linked to learner
    learner.reload
    assert_includes learner.parent_ids, @parent.id
  end

  test "POST /api/v1/invitations/match_by_phone includes failure reasons in response when link fails" do
    # Create invitation with matching phone but NO valid learner numbers or ids
    invitation = Invitation.new(
      token: "failing_accept_test_token",
      recipient_phone_number: "0620670152",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      role: "parent",
      status: "pending",
      learner_numbers: ["NONEXISTENT_ACC"]
    )
    invitation.save!(validate: false)

    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "0620670152",
      auth0_id: @parent.auth0_id,
      school_id: @school.id.to_s
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal 1, json_response['matched_count']

    # Response should contain the invitation with error details
    failing_inv = json_response['invitations'].first
    assert_equal false, failing_inv['success']
    assert_equal "No learners found for this invitation", failing_inv['error']
  end
end
