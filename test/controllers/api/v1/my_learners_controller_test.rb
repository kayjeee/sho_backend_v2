# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Fixture data is loaded from test/fixtures/
      @parent = users(:parent_one)
      @linked_learner = learners(:learner_one)
      @unlinked_learner = learners(:learner_two)

      # Ensure the data model is correct for the test:
      # Link learner_one to the parent using the explicit `parent_auth0_ids` array.
      @linked_learner.update!(parent_auth0_ids: [@parent.auth0_id])

      # Ensure learner_two is NOT linked to this parent.
      @unlinked_learner.update!(parent_auth0_ids: ['some-other-parent-auth0-id'])
    end

    test 'should return only linked learners when given a valid parent_auth0_id' do
      # --- ARRANGE ---
      # No authentication mocking is needed. The request is public.

      # --- ACT ---
      # Make a GET request to the new nested URL, passing the parent's auth0_id in the path.
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      # --- ASSERT ---
      assert_response :success

      response_json = JSON.parse(response.body)

      # Verify the response contains exactly one learner.
      assert_equal 1, response_json['count']

      # Verify that the learner in the response is the correct one.
      returned_learner_ids = response_json['learners'].map { |l| l['id'] }
      assert_includes returned_learner_ids, @linked_learner.id.to_s

      # CRITICAL: Verify that the unlinked learner is NOT present in the response.
      # This confirms the query is secure and does not leak data.
      assert_not_includes returned_learner_ids, @unlinked_learner.id.to_s
    end

    test 'should return not_found if the parent_auth0_id does not exist' do
      # --- ARRANGE ---
      invalid_parent_id = 'non-existent-auth0-id'

      # --- ACT ---
      # Make a request with an ID that does not correspond to any user in the database.
      get "/api/v1/parents/#{invalid_parent_id}/my_learners"

      # --- ASSERT ---
      # Verify that the controller correctly returns a 404 Not Found status.
      assert_response :not_found

      response_json = JSON.parse(response.body)
      assert_equal 'Parent not found', response_json['error']
    end

    test 'should return an empty array if parent exists but has no linked learners' do
      # --- ARRANGE ---
      # Create a parent who has no learners linked to them.
      parent_with_no_learners = users(:parent_two)
      @linked_learner.update!(parent_auth0_ids: ['some-other-parent-auth0-id']) # Ensure it's not linked

      # --- ACT ---
      get "/api/v1/parents/#{parent_with_no_learners.auth0_id}/my_learners"

      # --- ASSERT ---
      assert_response :success

      response_json = JSON.parse(response.body)
      assert_equal 0, response_json['count']
      assert_empty response_json['learners']
    end
  end
end
