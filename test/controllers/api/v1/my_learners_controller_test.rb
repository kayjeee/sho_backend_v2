# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'
require 'mocha/minitest' # Ensure mocha is required for mocking

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Fixture data is loaded from test/fixtures/
      @user = users(:parent_one)
      @linked_learner = learners(:learner_one)
      @unlinked_learner = learners(:learner_two)

      # Ensure the data model is correct for the test:
      # Link learner_one to parent_one using the new, secure mechanism.
      @linked_learner.update!(parent_auth0_ids: [@user.auth0_id])

      # Ensure learner_two is not linked to parent_one.
      @unlinked_learner.update!(parent_auth0_ids: ['some-other-auth0-id'])
    end

    test 'should return only linked learners for an authenticated user' do
      # --- ARRANGE ---
      # Mock the authentication layer (the `authorize` method from `Secured` concern).
      # We simulate a successful authentication by making `authorize` do nothing
      # and then manually setting the decoded token that `authorize` would normally provide.
      Api::V1::MyLearnersController.any_instance.stubs(:authorize).returns(true)

      # The controller's `index` action expects `@decoded_token` to be set by `authorize`.
      # We'll simulate this by setting it directly on the controller instance.
      # The token payload must contain the user's Auth0 ID in the 'sub' claim.
      decoded_token = mock()
      decoded_token.stubs(:token).returns({ 'sub' => @user.auth0_id })
      Api::V1::MyLearnersController.any_instance.stubs(:instance_variable_get).with(:@decoded_token).returns(decoded_token)

      # --- ACT ---
      # Make the request to the secure endpoint. No special headers are needed
      # because we have mocked the authentication check.
      get api_v1_my_learners_url

      # --- ASSERT ---
      assert_response :success

      response_json = JSON.parse(response.body)

      # Verify the response contains exactly one learner.
      assert_equal 1, response_json['count']

      # Verify that the learner in the response is the correct one.
      returned_learner_ids = response_json['learners'].map { |l| l['id'] }
      assert_includes returned_learner_ids, @linked_learner.id.to_s

      # CRITICAL: Verify that the unlinked learner is NOT present in the response.
      assert_not_includes returned_learner_ids, @unlinked_learner.id.to_s
    end

    test 'should return unauthorized if authentication fails' do
      # --- ARRANGE ---
      # This time, we don't mock `authorize`. We let it run.
      # To simulate a failure, we mock the `Auth0Client` that `authorize` depends on.
      # We make it return an error object, just like it would for an invalid token.
      error_response = OpenStruct.new(
        error: OpenStruct.new(message: 'Requires authentication', status: :unauthorized)
      )
      Auth0Client.stubs(:validate_token).returns(error_response)

      # --- ACT ---
      # Make a request with a fake bearer token (it doesn't matter what it is,
      # since our mock will intercept the validation).
      get api_v1_my_learners_url, headers: { 'Authorization' => 'Bearer fake-token' }

      # --- ASSERT ---
      # Verify that the controller correctly returns an unauthorized status.
      assert_response :unauthorized

      response_json = JSON.parse(response.body)
      assert_equal 'Requires authentication', response_json['message']
    end
  end
end
