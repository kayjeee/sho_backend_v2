# test/controllers/api/v1/learner_links_controller_test.rb
require 'test_helper'

module Api::V1
  class LearnerLinksControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)
      @learner = learners(:learner_one)
      @user.schools << @school unless @user.schools.include?(@school)
      @learner.update(school_id: @school.id)
    end

    test "should link learner to user" do
      post '/api/v1/learners/link', params: {
        learner_number: @learner.accession_number,
        user_email: @user.email
      }

      assert_response :created
      @user.reload
      assert_includes @user.learner_ids, @learner.id
    end

    test "should not link learner if already linked" do
      @user.push(learner_ids: @learner.id)

      post '/api/v1/learners/link', params: {
        learner_number: @learner.accession_number,
        user_email: @user.email
      }

      assert_response :ok
      assert_equal 'Learner already linked', JSON.parse(response.body)['message']
    end

    test "should not link learner if learner not found" do
      post '/api/v1/learners/link', params: {
        learner_number: 'invalid-number',
        user_email: @user.email
      }

      assert_response :not_found
    end

    test "should not link learner if user not found" do
      post '/api/v1/learners/link', params: {
        learner_number: @learner.accession_number,
        user_email: 'invalid-email@example.com'
      }

      assert_response :not_found
    end

    test "should not link learner if learner is not in user's school" do
      other_school = schools(:school_two)
      @learner.update(school_id: other_school.id)

      post '/api/v1/learners/link', params: {
        learner_number: @learner.accession_number,
        user_email: @user.email
      }

      assert_response :forbidden
    end
  end
end
