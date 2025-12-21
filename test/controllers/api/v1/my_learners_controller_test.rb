# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @parent = users(:parent_one)
      @school = schools(:school_one)
      @other_school = schools(:school_two)

      # Ensure parent belongs to school_one but not school_two
      @parent.schools << @school unless @parent.schools.include?(@school)
      @parent.schools.delete(@other_school)

      @learner_in_school = learners(:learner_one)
      @learner_in_other_school = learners(:learner_two)

      # Link parent to BOTH learners
      @learner_in_school.update!(parent_auth0_ids: [@parent.auth0_id], school_id: @school.id)
      @learner_in_other_school.update!(parent_auth0_ids: [@parent.auth0_id], school_id: @other_school.id)
    end

    # --- Primary Security Test ---
    test 'should return ONLY linked learners that are in the parent\'s school' do
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)

      # Assert that only ONE learner is returned
      assert_equal 1, response_json['count']

      returned_ids = response_json['learners'].map { |l| l['id'] }

      # Assert that the correct learner IS present
      assert_includes returned_ids, @learner_in_school.id.to_s

      # CRITICAL: Assert that the learner from the other school IS NOT present,
      # even though the parent is linked to them.
      assert_not_includes returned_ids, @learner_in_other_school.id.to_s
    end

    # --- Profile Endpoint Test ---
    test 'GET /parents/:id/profile should return parent profile and the CORRECT learner count' do
      get "/api/v1/parents/#{@parent.auth0_id}/profile"

      assert_response :success
      response_json = JSON.parse(response.body)

      assert_not_nil response_json['parent']
      assert_equal @parent.auth0_id, response_json['parent']['auth0_id']

      # The count must also respect the school scoping.
      assert_equal 1, response_json['learner_count']
    end

    # --- Edge Case Tests ---
    test 'should return not_found for a non-existent auth0_id' do
      get "/api/v1/parents/non-existent-id/my_learners"
      assert_response :not_found

      get "/api/v1/parents/non-existent-id/profile"
      assert_response :not_found
    end

    test 'should return an empty array if parent has no valid learners' do
      # Make sure the parent has no learners that meet both criteria
      @learner_in_school.update!(parent_auth0_ids: ['some-other-id'])
      @learner_in_other_school.update!(parent_auth0_ids: ['some-other-id'])

      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal 0, response_json['count']
      assert_empty response_json['learners']
    end
  end
end
