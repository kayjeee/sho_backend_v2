# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)

      # Learner to be linked via the new learner_ids mechanism
      @new_learner = learners(:learner_one)

      # Learner to be linked via the legacy parent_info.auth0_id mechanism
      @legacy_learner = learners(:learner_two)
      @legacy_learner.update(parent_info: { auth0_id: @user.auth0_id })

      # An unassociated learner in the same school that should never be returned
      @other_learner = learners(:learner_three)
      @other_learner.update(school_id: @school.id)
    end

    test 'should return ONLY new learners if user has learner_ids' do
      @user.update(learner_ids: [@new_learner.id.to_s])

      get '/api/v1/my_learners', headers: { 'X-User-Email' => @user.email }

      assert_response :success
      response_json = JSON.parse(response.body)
      learner_ids = response_json['learners'].map { |l| l['id'] }

      assert_equal 1, response_json['learner_count']
      assert_includes learner_ids, @new_learner.id.to_s
      assert_not_includes learner_ids, @legacy_learner.id.to_s, "Should not include legacy learners if learner_ids is present"
      assert_not_includes learner_ids, @other_learner.id.to_s, "Should not include unassociated learners from the same school"
    end

    test 'should return ONLY legacy learners if user has no learner_ids' do
      @user.update(learner_ids: []) # Ensure no new links exist

      get '/api/v1/my_learners', headers: { 'X-User-Email' => @user.email }

      assert_response :success
      response_json = JSON.parse(response.body)
      learner_ids = response_json['learners'].map { |l| l['id'] }

      assert_equal 1, response_json['learner_count']
      assert_includes learner_ids, @legacy_learner.id.to_s
      assert_not_includes learner_ids, @new_learner.id.to_s
      assert_not_includes learner_ids, @other_learner.id.to_s, "Should not include unassociated learners from the same school"
    end

    test 'should return parent object for legacy /profile route' do
      get "/api/v1/parents/#{@user.auth0_id}/profile"
      assert_response :success
      response_json = JSON.parse(response.body)

      assert_not_nil response_json['parent']
      assert_equal @user.auth0_id, response_json['parent']['auth0_id']
    end
  end
end
