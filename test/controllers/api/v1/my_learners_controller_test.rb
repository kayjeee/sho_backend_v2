# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'
require 'mocha/minitest'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @parent = users(:parent_one)
      @school = schools(:school_one)
      @other_school = schools(:school_two)

      @parent.schools.add(@school)
      @parent.schools.delete(@other_school)

      # Learner linked via the new array model in the correct school
      @learner_in_school = learners(:learner_one)
      @learner_in_school.update!(parent_auth0_ids: [@parent.auth0_id], school_id: @school.id)

      # Learner linked via the array model but in the wrong school
      @learner_wrong_school = learners(:learner_two)
      @learner_wrong_school.update!(parent_auth0_ids: [@parent.auth0_id], school_id: @other_school.id)
    end

    test 'should return only linked learners that are in the parent\'s school' do
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)

      assert_equal 1, response_json['learner_count']

      returned_ids = response_json['learners'].map { |l| l['id'] }
      assert_includes returned_ids, @learner_in_school.id.to_s
      assert_not_includes returned_ids, @learner_wrong_school.id.to_s
    end

    test 'GET /parents/:id/profile should return profile and correct learner count' do
      get "/api/v1/parents/#{@parent.auth0_id}/profile"
      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal 1, response_json['learner_count']
    end

    test 'should return not_found for a non-existent auth0_id' do
      get "/api/v1/parents/non-existent-id/my_learners"
      assert_response :not_found
    end
  end
end
