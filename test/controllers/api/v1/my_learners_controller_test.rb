# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @learner = learners(:learner_one)
    end

    test 'should return learners if user has learner_ids' do
      @user.update(learner_ids: [@learner.id.to_s])
      get '/api/v1/my_learners', headers: { 'X-User-Email' => @user.email }

      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal 1, response_json['learner_count']
      assert_equal @learner.id.to_s, response_json['learners'].first['id']
    end

    test 'should return no learners if user has no learner_ids' do
      @user.update(learner_ids: [])
      get '/api/v1/my_learners', headers: { 'X-User-Email' => @user.email }

      assert_response :success
      response_json = JSON.parse(response.body)
      assert_equal 0, response_json['learner_count']
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
