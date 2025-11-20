# test/controllers/api/v1/invitations_controller_test.rb
require 'test_helper'

class Api::V1::InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invitation = invitations(:one)
  end

  test "should verify invitation with valid token" do
    post verify_api_v1_invitations_url, params: { token: @invitation.token }
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal true, json_response['success']
    assert_equal 'Invitation verified successfully.', json_response['message']
    @invitation.reload
    assert_equal 'verified', @invitation.status
  end

  test "should not verify invitation with invalid token" do
    post verify_api_v1_invitations_url, params: { token: 'invalid-token' }
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_equal 'Invalid or expired invitation link.', json_response['message']
  end

  test "should not verify invitation if update fails" do
    Invitation.any_instance.stubs(:update).returns(false)
    post verify_api_v1_invitations_url, params: { token: @invitation.token }
    assert_response :unprocessable_entity
  end
end
