# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one) # A user with associated schools
      @school = schools(:school_one)

      # Ensure user is associated with the school
      @user.schools << @school unless @user.schools.include?(@school)

      # Learner linked via the new learner_ids mechanism
      @new_learner = learners(:learner_one)
      @user.update(learner_ids: [@new_learner.id.to_s])

      # Learner linked via the legacy parent_info.auth0_id mechanism
      @legacy_learner = learners(:learner_two)
      @legacy_learner.update(
        school_id: @school.id,
        parent_info: { auth0_id: @user.auth0_id }
      )

      # An unassociated learner that should not be returned
      @other_learner = learners(:learner_three)
    end

    # --- Tests for the new /my_learners route ---

    test 'should get all associated learners for a user via my_learners route' do
      get '/api/v1/my_learners', headers: { 'X-User-Email' => @user.email }

      assert_response :success

      response_json = JSON.parse(response.body)
      learner_ids = response_json['learners'].map { |l| l['id'] }

      assert_equal 2, response_json['learner_count']
      assert_includes learner_ids, @new_learner.id.to_s
      assert_includes learner_ids, @legacy_learner.id.to_s
      assert_not_includes learner_ids, @other_learner.id.to_s
      assert_nil response_json['parent']
    end

    # --- Tests for the legacy /parents routes ---

    test 'should get all associated learners via legacy parents/learners route' do
      get "/api/v1/parents/#{@user.auth0_id}/learners"
      assert_response :success

      response_json = JSON.parse(response.body)
      learner_ids = response_json['learners'].map { |l| l['id'] }

      assert_equal 2, response_json['learner_count']
      assert_includes learner_ids, @new_learner.id.to_s
      assert_includes learner_ids, @legacy_learner.id.to_s
      assert_nil response_json['parent']
    end

    test 'should get all associated learners and parent object via legacy parents/profile route' do
      get "/api/v1/parents/#{@user.auth0_id}/profile"
      assert_response :success

      response_json = JSON.parse(response.body)

      assert_equal 2, response_json['learner_count']
      assert_not_nil response_json['parent']
      assert_equal @user.auth0_id, response_json['parent']['auth0_id']
    end

    test "should return 'not found' for legacy route if parent does not exist" do
      get "/api/v1/parents/nonexistent-id/learners"
      assert_response :not_found
    end
  end
end
