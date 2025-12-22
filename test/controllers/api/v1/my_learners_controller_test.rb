# test/controllers/api/v1/my_learners_controller_test.rb
require 'test_helper'
require 'mocha/minitest'

module Api::V1
  class MyLearnersControllerTest < ActionDispatch::IntegrationTest
    setup do
      @parent = users(:parent_one)
      @school = schools(:school_one)
      @other_school = schools(:school_two)

      # Associate parent with the correct school
      @parent.school_ids = [@school.id.to_s]
      @parent.save!

      # Learner linked via `auth0Id` (legacy)
      @learner_legacy_auth0Id = learners(:learner_one)
      @learner_legacy_auth0Id.update!(
        auth0Id: @parent.auth0_id,
        school_id: @school.id.to_s,
        status: 0 # active
      )

      # Learner linked via `userAuth0Id` (legacy)
      @learner_legacy_userAuth0Id = learners(:learner_two)
      @learner_legacy_userAuth0Id.update!(
        userAuth0Id: @parent.auth0_id,
        school_id: @school.id.to_s,
        status: 0 # active
      )

      # Learner linked via `parent_auth0_ids` (new)
      @learner_new_model = Learner.create!(
        first_name: 'New',
        last_name: 'Model',
        accession_number: '777',
        parent_auth0_ids: [@parent.auth0_id],
        school_id: @school.id.to_s,
        status: 0 # active
      )

      # Unlinked learner in the same school
      @unlinked_learner = learners(:learner_three)
      @unlinked_learner.update!(
        auth0Id: 'some-other-auth0-id',
        school_id: @school.id.to_s,
        status: 0 # active
      )

      # Learner in the wrong school
      @learner_wrong_school = Learner.create!(
        first_name: 'Wrong',
        last_name: 'School',
        accession_number: '999',
        auth0Id: @parent.auth0_id,
        school_id: @other_school.id.to_s,
        status: 0 # active
      )

      # Inactive learner
      @inactive_learner = Learner.create!(
        first_name: 'Inactive',
        last_name: 'Learner',
        accession_number: '888',
        auth0Id: @parent.auth0_id,
        school_id: @school.id.to_s,
        status: 1 # inactive
      )
    end

    test 'should return only active, linked learners from the new model' do
      get "/api/v1/parents/#{@parent.auth0_id}/my_learners"

      assert_response :success
      response_json = JSON.parse(response.body)

      assert_equal 1, response_json['learner_count'], "Expected 1 learner, but found #{response_json['learner_count']}"

      returned_ids = response_json['learners'].map { |l| l['id'] }
      assert_not_includes returned_ids, @learner_legacy_auth0Id.id.to_s
      assert_not_includes returned_ids, @learner_legacy_userAuth0Id.id.to_s
      assert_includes returned_ids, @learner_new_model.id.to_s
      assert_not_includes returned_ids, @unlinked_learner.id.to_s
      assert_not_includes returned_ids, @learner_wrong_school.id.to_s
      assert_not_includes returned_ids, @inactive_learner.id.to_s
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
