# test/controllers/api/v1/invitations_controller_test.rb
require 'test_helper'

module Api::V1
  class InvitationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)
      @learner = learners(:learner_one)
      @invitation = invitations(:one)
    end

    test "should create invitation" do
      post api_v1_invitations_url, params: {
        phone_number: '1234567890',
        school_id: @school.id.to_s,
        learner_number: @learner.accession_number,
        user_email: @user.email
      }
      assert_response :created
      json_response = JSON.parse(response.body)
      assert json_response['success']
      assert_not_nil json_response['invitation']['token']
    end

    test "should verify invitation and link learner" do
      post verify_api_v1_invitations_url, params: { token: @invitation.token, user_email: @user.email }
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
        school_id: @school.id.to_s,
        user_email: @user.email
      }
      assert_response :unprocessable_entity
    end

    test "should return not found for invalid token on verify" do
      post verify_api_v1_invitations_url, params: { token: 'invalid-token', user_email: @user.email }
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
