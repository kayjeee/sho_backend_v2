# test/controllers/api/v1/invitations_controller_test.rb
require 'test_helper'
require 'mocha/minitest'

module Api::V1
  class InvitationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)
      @learner = learners(:learner_one)
      @invitation = invitations(:one)

      # Stub the authorization for all tests in this class
      Api::V1::InvitationsController.any_instance.stubs(:authorize).returns(true)
      Api::V1::InvitationsController.any_instance.stubs(:current_user).returns(@user)
    end

    test "should create invitation when authenticated" do
      post api_v1_invitations_url, params: {
        phone_number: '1234567890',
        school_id: @school.id.to_s,
        learner_number: @learner.accession_number
      }
      assert_response :created
      json_response = JSON.parse(response.body)
      assert json_response['success']
      assert_not_nil json_response['invitation']['token']
    end

    test "should verify invitation and link learner when authenticated" do
      post verify_api_v1_invitations_url, params: { token: @invitation.token }
      assert_response :ok
      json_response = JSON.parse(response.body)
      assert json_response['success']
      assert json_response['linked']
      @user.reload
      assert_includes @user.learner_ids, @invitation.learner_ids.first
    end

    test "should not create invitation without learner number" do
      post api_v1_invitations_url, params: {
        phone_number: '1234567890',
        school_id: @school.id.to_s
      }
      assert_response :unprocessable_entity
    end

    test "should return not found for invalid token on verify" do
      post verify_api_v1_invitations_url, params: { token: 'invalid-token' }
      assert_response :not_found
    end

    test "should get invitation details with valid token" do
      get "/invitations/#{@invitation.token}/verify_with_details"
      assert_response :success
      json_response = JSON.parse(response.body)
      assert json_response['success']
      assert_equal @invitation.id.to_s, json_response['invitation']['id']
    end
  end
end
