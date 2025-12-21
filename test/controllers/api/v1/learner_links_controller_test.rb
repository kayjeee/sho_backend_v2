# test/controllers/api/v1/learner_links_controller_test.rb
require 'test_helper'
require 'mocha/minitest'

module Api::V1
  class LearnerLinksControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:parent_one)
      @school = schools(:school_one)
      @learner = learners(:learner_one)

      # Ensure learner starts unassigned and in the correct school
      @learner.update!(school_id: @school.id, auth0Id: nil, userAuth0Id: nil)
    end

    def mock_authentication(user)
      Api::V1::LearnerLinksController.any_instance.stubs(:authorize).returns(true)
      decoded_token = mock()
      decoded_token.stubs(:token).returns({ 'sub' => user.auth0_id })
      Api::V1::LearnerLinksController.any_instance.stubs(:instance_variable_get).with(:@decoded_token).returns(decoded_token)
    end

    test "should link learner by setting auth0Id on the learner document" do
      mock_authentication(@user)
      assert_nil @learner.auth0Id

      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }

      assert_response :created
      @learner.reload
      assert_equal @user.auth0_id, @learner.auth0Id
    end

    test "should return ok if learner is already linked to the same user via auth0Id" do
      @learner.update!(auth0Id: @user.auth0_id)
      mock_authentication(@user)

      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }

      assert_response :ok
      assert_equal 'Learner already linked to your account', JSON.parse(response.body)['message']
    end

    test "should return ok if learner is already linked to the same user via userAuth0Id" do
      @learner.update!(userAuth0Id: @user.auth0_id)
      mock_authentication(@user)

      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }

      assert_response :ok
      assert_equal 'Learner already linked to your account', JSON.parse(response.body)['message']
    end

    test "should return conflict if learner is already assigned to another parent" do
      @learner.update!(auth0Id: 'some-other-parent-id')
      mock_authentication(@user)

      post api_v1_learner_links_url, params: {
        accession_number: @learner.accession_number,
        school_id: @school.id.to_s
      }

      assert_response :conflict
    end
  end
end
