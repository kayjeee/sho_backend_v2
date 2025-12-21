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

      # Learner linked via `auth0Id`
      @learner1 = learners(:learner_one)
      @learner1.update!(auth0Id: @parent.auth0_id, school_id: @school.id)

      # Learner linked via `userAuth0Id`
      @learner2 = learners(:learner_two)
      @learner2.update!(userAuth0Id: @parent.auth0_id, school_id: @school.id)

      # Learner linked but in the wrong school
      @learner_wrong_school = learners(:learner_three)
      @learner_wrong_school.update!(auth0Id: @parent.auth0_id, school_id: @other_school.id)
    end

    test 'should return all valid learners from correct school' do
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)

      assert_equal 2, response_json['learner_count']

      returned_ids = response_json['learners'].map { |l| l['id'] }
      assert_includes returned_ids, @learner1.id.to_s
      assert_includes returned_ids, @learner2.id.to_s
      assert_not_includes returned_ids, @learner_wrong_school.id.to_s
    end

    test 'GET /my_learners with JWT should also return all valid learners' do
      Api::V1::MyLearnersController.any_instance.stubs(:authorize).returns(true)
      decoded_token = mock()
      decoded_token.stubs(:token).returns({ 'sub' => @parent.auth0_id })
      Api::V1::MyLearnersController.any_instance.stubs(:instance_variable_get).with(:@decoded_token).returns(decoded_token)

      get '/api/v1/my_learners'

      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal 2, response_json['learner_count']
    end

    test 'GET /parents/:id/profile should return correct, unified count' do
      get "/api/v1/parents/#{@parent.auth0_id}/profile"
      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal 2, response_json['learner_count']
    end
  end
end
