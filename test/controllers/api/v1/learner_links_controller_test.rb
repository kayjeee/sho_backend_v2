# test/controllers/api/v1/learner_links_controller_test.rb
require 'test_helper'
require 'mocha/minitest'

module Api::V1
  class LearnerLinksControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)
      @learner = learners(:learner_one)

      # Ensure the learner belongs to the correct school for the test scenario
      @learner.update!(school_id: @school.id)
    end

    def mock_authentication(user)
      # Mock the `authorize` method to simulate a successful login
      Api::V1::LearnerLinksController.any_instance.stubs(:authorize).returns(true)

      # Mock the decoded token that `authorize` would provide
      decoded_token = mock()
      decoded_token.stubs(:token).returns({ 'sub' => user.auth0_id })
      Api::V1::LearnerLinksController.any_instance.stubs(:instance_variable_get).with(:@decoded_token).returns(decoded_token)
    end

    test "should link learner to authenticated user with correct accession number and school_id" do
      # --- ARRANGE ---
      mock_authentication(@user)
      assert_not_includes @learner.parent_auth0_ids, @user.auth0_id

      # --- ACT ---
      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }

      # --- ASSERT ---
      assert_response :created
      @learner.reload
      assert_includes @learner.parent_auth0_ids, @user.auth0_id
    end

    test "should return ok if learner is already linked" do
      # --- ARRANGE ---
      # Manually link the learner first
      @learner.update!(parent_auth0_ids: [@user.auth0_id])
      mock_authentication(@user)

      # --- ACT ---
      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }

      # --- ASSERT ---
      assert_response :ok
      assert_equal 'Learner already linked', JSON.parse(response.body)['message']
    end

    test "should return not_found if learner does not exist" do
      # --- ARRANGE ---
      mock_authentication(@user)

      # --- ACT ---
      post api_v1_learner_links_url, params: {
        accession_number: 'invalid-accession-number',
        school_id: @school.id.to_s
      }

      # --- ASSERT ---
      assert_response :not_found
    end

    test "should return unprocessable_entity if parameters are missing" do
      # --- ARRANGE ---
      mock_authentication(@user)

      # --- ACT ---
      post api_v1_learner_links_url, params: { accession_number: @learner.accession_number } # Missing school_id

      # --- ASSERT ---
      assert_response :unprocessable_entity
    end

    test "should return unauthorized for unauthenticated request" do
      # --- ARRANGE ---
      # We do NOT mock authentication. Instead, we mock the client to ensure it fails.
      error_response = OpenStruct.new(
        error: OpenStruct.new(message: 'Requires authentication', status: :unauthorized)
      )
      Auth0Client.stubs(:validate_token).returns(error_response)

      # --- ACT ---
      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }, headers: { 'Authorization' => 'Bearer fake-token' }

      # --- ASSERT ---
      assert_response :unauthorized
    end
  end
end
