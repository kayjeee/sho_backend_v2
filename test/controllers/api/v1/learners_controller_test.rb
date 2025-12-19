# test/controllers/api/v1/learners_controller_test.rb
require 'test_helper'

module Api::V1
  class LearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)
      @learner = learners(:learner_one)
      @user.schools << @school unless @user.schools.include?(@school)
    end

    test "should link learner to user" do
      post link_api_v1_learners_url, params: {
        learner_number: @learner.accession_number
      }, headers: { 'X-User-Email' => @user.email }

      assert_response :success
      @user.reload
      assert_includes @user.learner_ids, @learner.id.to_s
    end
  end
end
