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

    test 'should get all associated learners for an authenticated user' do
      get '/api/v1/my_learners', headers: { 'X-User-Auth0-Id' => @user.auth0_id }

      assert_response :success

      response_json = JSON.parse(response.body)
      learner_ids = response_json['learners'].map { |l| l['id'] }

      assert_equal 2, response_json['learner_count']
      assert_includes learner_ids, @new_learner.id.to_s
      assert_includes learner_ids, @legacy_learner.id.to_s
      assert_not_includes learner_ids, @other_learner.id.to_s
    end

    test 'should return empty array if user has no learners' do
      new_user = users(:user_without_learners)
      get '/api/v1/my_learners', headers: { 'X-User-Auth0-Id' => new_user.auth0_id }

      assert_response :success

      response_json = JSON.parse(response.body)
      assert_equal 0, response_json['learner_count']
      assert_equal [], response_json['learners']
    end

    test 'should not return learners if unauthenticated' do
      # Note: This test assumes the placeholder authenticate_user! logic from the controller,
      # which should be replaced by the app's actual authentication.
      # If the app's auth works differently, this test may need adjustment.
      get '/api/v1/my_learners'

      assert_response :unauthorized
    end
  end
end
