# test/controllers/api/v1/parents_controller_test.rb
require 'test_helper'

module Api::V1
  class ParentsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @parent = users(:parent_one)
      @learner1 = learners(:learner_one)
      @learner2 = learners(:learner_two)
      @other_learner = learners(:learner_three)
    end

    test 'should get learners for a specific parent' do
      get "/api/v1/parents/#{@parent.auth0_id}/learners"
      assert_response :success

      learners_response = JSON.parse(response.body)
      assert_equal 2, learners_response.size
      assert_equal @learner1.id.to_s, learners_response.first['id']
    end

    test "should return 'not found' if parent does not exist" do
      get "/api/v1/parents/nonexistent-id/learners"
      assert_response :not_found
    end
  end
end
