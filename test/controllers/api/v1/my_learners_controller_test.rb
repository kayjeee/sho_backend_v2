# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @parent = users(:parent_one)
      @school = schools(:school_one)
      @other_school = schools(:school_two)

      @parent.schools.add(@school)
      @parent.schools.delete(@other_school)

      # Learner linked via `auth0Id` in the correct school
      @learner1 = learners(:learner_one)
      @learner1.update!(auth0Id: @parent.auth0_id, school_id: @school.id)

      # Learner linked via `userAuth0Id` in the correct school
      @learner2 = learners(:learner_two)
      @learner2.update!(userAuth0Id: @parent.auth0_id, school_id: @school.id)

      # Learner linked but in a school the parent does not belong to
      @learner_wrong_school = learners(:learner_three)
      @learner_wrong_school.update!(auth0Id: @parent.auth0_id, school_id: @other_school.id)
    end

    test 'GET /parents/:auth0_id/my_learners should return only learners from the correct school' do
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)

      assert_equal 2, response_json['learner_count']

      returned_ids = response_json['learners'].map { |l| l['id'] }
      assert_includes returned_ids, @learner1.id.to_s
      assert_includes returned_ids, @learner2.id.to_s
      assert_not_includes returned_ids, @learner_wrong_school.id.to_s
    end

    test 'GET /parents/:auth0_id/profile should return the correct, school-scoped learner count' do
      get "/api/v1/parents/#{@parent.auth0_id}/profile"
      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal @parent.auth0_id, response_json['parent']['auth0_id']
      assert_equal 2, response_json['learner_count']
    end

    test 'should return not_found for a non-existent auth0_id' do
      get "/api/v1/parents/non-existent-id/my_learners"
      assert_response :not_found
    end
  end
end
