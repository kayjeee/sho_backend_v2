# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'
require 'mocha/minitest'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @parent = users(:parent_one)
      @linked_learner = learners(:learner_one)
      @unlinked_learner = learners(:learner_two)

      # Link learner_one to the parent to set up the main test condition
      @linked_learner.update!(parent_auth0_ids: [@parent.auth0_id])
      # Ensure learner_two is explicitly unlinked for security checks
      @unlinked_learner.update!(parent_auth0_ids: ['some-other-parent-id'])
    end

    # --- Test Case 1: New Unauthenticated Route ---
    test 'GET /parents/:id/my_learners should return only linked learners without auth' do
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)

      # Assert correct JSON shape for the new route
      assert_equal 1, response_json['count']
      assert_equal 1, response_json['learners'].count
      assert_equal @linked_learner.id.to_s, response_json['learners'].first['id']

      # Assert data security
      returned_ids = response_json['learners'].map { |l| l['id'] }
      assert_not_includes returned_ids, @unlinked_learner.id.to_s
    end

    # --- Test Case 2: Legacy Authenticated Route ---
    test 'GET /my_learners should return linked learners with JWT auth' do
      # Mock the JWT authentication
      Api::V1::MyLearnersController.any_instance.stubs(:authorize).returns(true)
      decoded_token = mock()
      decoded_token.stubs(:token).returns({ 'sub' => @parent.auth0_id })
      Api::V1::MyLearnersController.any_instance.stubs(:instance_variable_get).with(:@decoded_token).returns(decoded_token)

      get '/api/v1/my_learners'

      assert_response :success
      response_json = JSON.parse(response.body)

      # Assert correct JSON shape for the LEGACY route ("learner_count")
      assert_equal 1, response_json['learner_count']
      assert_equal 1, response_json['learners'].count
      assert_equal @linked_learner.id.to_s, response_json['learners'].first['id']
    end

    # --- Test Case 3: Legacy Profile Route ---
    test 'GET /parents/:id/profile should return parent profile and count' do
      get "/api/v1/parents/#{@parent.auth0_id}/profile"

      assert_response :success
      response_json = JSON.parse(response.body)

      # Assert correct JSON shape for the LEGACY profile route
      assert_not_nil response_json['parent']
      assert_equal @parent.auth0_id, response_json['parent']['auth0_id']
      assert_equal 1, response_json['learner_count']
    end

    # --- Edge Case Test ---
    test 'should return not_found for a non-existent parent_auth0_id' do
      get "/api/v1/parents/non-existent-id/my_learners"
      assert_response :not_found

      get "/api/v1/parents/non-existent-id/profile"
      assert_response :not_found
    end
  end
end
