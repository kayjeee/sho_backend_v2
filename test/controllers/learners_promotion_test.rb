require 'test_helper'

class LearnersPromotionTest < ActionDispatch::IntegrationTest
  setup do
    Mongoid.purge!

    @school = School.create!(
      schoolName: "Promotion Secondary School",
      schoolEmail: "promo@school.com"
    )

    @other_school = School.create!(
      schoolName: "Other School",
      schoolEmail: "other_school@test.com"
    )

    @grade6 = Grade.create!(
      name: "Grade 6",
      level: 6,
      school: @school
    )

    @grade7 = Grade.create!(
      name: "Grade 7",
      level: 7,
      school: @school
    )

    @learner1 = Learner.create!(
      firstName: "Kagiso",
      lastName: "Sebogodi",
      accessionNumber: "KAG001",
      school_id: @school.id.to_s,
      grade_id: @grade6.id.to_s,
      academic_year: "2026",
      status: 0,
      gender: 0
    )

    @learner2 = Learner.create!(
      firstName: "Thabo",
      lastName: "Mbeki",
      accessionNumber: "THA002",
      school_id: @school.id.to_s,
      grade_id: @grade6.id.to_s,
      academic_year: "2026",
      status: 0,
      gender: 0
    )
  end

  test "Test 1 - Single learner promotion from 2026 Grade 6 to 2027 Grade 7" do
    payload = {
      school_id: @school.id.to_s,
      source_academic_year: "2026",
      destination_academic_year: "2027",
      source_grade_id: @grade6.id.to_s,
      destination_grade_id: @grade7.id.to_s,
      learner_ids: [@learner1.id.to_s]
    }

    post "/api/v1/learners/promote", params: payload
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal 1, json_response['stats']['promoted_count']
    assert_equal 0, json_response['stats']['failed_count']
    assert_equal 0, json_response['stats']['skipped_count']

    # Verify Learner database record
    @learner1.reload
    assert_equal "2027", @learner1.academic_year
    assert_equal @grade7.id.to_s, @learner1.grade_id.to_s

    # Verify history preserved
    assert_equal 1, @learner1.academic_history.size
    history_entry = @learner1.academic_history.first
    assert_equal "2026", history_entry['source_academic_year']
    assert_equal "2027", history_entry['destination_academic_year']
    assert_equal "Grade 6", history_entry['source_grade_name']
    assert_equal "Grade 7", history_entry['destination_grade_name']
  end

  test "Test 2 - Bulk learners promotion" do
    payload = {
      school_id: @school.id.to_s,
      source_academic_year: "2026",
      destination_academic_year: "2027",
      source_grade_id: @grade6.id.to_s,
      destination_grade_id: @grade7.id.to_s,
      learner_ids: [@learner1.id.to_s, @learner2.id.to_s]
    }

    post "/api/v1/learners/promote", params: payload
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal 2, json_response['stats']['promoted_count']

    @learner1.reload
    @learner2.reload
    assert_equal @grade7.id.to_s, @learner1.grade_id.to_s
    assert_equal @grade7.id.to_s, @learner2.grade_id.to_s
  end

  test "Test 3 - Wrong grade rejection" do
    grade5 = Grade.create!(
      name: "Grade 5",
      level: 5,
      school: @school
    )

    learner_in_grade5 = Learner.create!(
      firstName: "Sipho",
      lastName: "Nkosi",
      accessionNumber: "SIP003",
      school_id: @school.id.to_s,
      grade_id: grade5.id.to_s,
      academic_year: "2026",
      status: 0,
      gender: 0
    )

    # Attempt to promote Grade 5 learner using source_grade_id = Grade 6
    payload = {
      school_id: @school.id.to_s,
      source_academic_year: "2026",
      destination_academic_year: "2027",
      source_grade_id: @grade6.id.to_s,
      destination_grade_id: @grade7.id.to_s,
      learner_ids: [learner_in_grade5.id.to_s]
    }

    post "/api/v1/learners/promote", params: payload
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)

    assert_equal false, json_response['success']
    assert_equal 1, json_response['stats']['failed_count']
    assert_match /not source grade/, json_response['failed'].first['reason']
  end

  test "Test 4 - Wrong school rejection" do
    other_school_grade6 = Grade.create!(
      name: "Grade 6",
      level: 6,
      school: @other_school
    )

    other_school_learner = Learner.create!(
      firstName: "Foreign",
      lastName: "Learner",
      accessionNumber: "FOR999",
      school_id: @other_school.id.to_s,
      grade_id: other_school_grade6.id.to_s,
      academic_year: "2026",
      status: 0,
      gender: 0
    )

    # Attempt to promote School B learner via School A promotion request
    payload = {
      school_id: @school.id.to_s,
      source_academic_year: "2026",
      destination_academic_year: "2027",
      source_grade_id: @grade6.id.to_s,
      destination_grade_id: @grade7.id.to_s,
      learner_ids: [other_school_learner.id.to_s]
    }

    post "/api/v1/learners/promote", params: payload
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)

    assert_equal false, json_response['success']
    assert_equal 1, json_response['stats']['failed_count']
    assert_match /does not belong to the specified school/, json_response['failed'].first['reason']
  end

  test "Test 5 - Duplicate promotion prevention" do
    payload = {
      school_id: @school.id.to_s,
      source_academic_year: "2026",
      destination_academic_year: "2027",
      source_grade_id: @grade6.id.to_s,
      destination_grade_id: @grade7.id.to_s,
      learner_ids: [@learner1.id.to_s]
    }

    # First promotion -> succeeds
    post "/api/v1/learners/promote", params: payload
    assert_response :success

    # Second identical promotion -> skipped
    post "/api/v1/learners/promote", params: payload
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal 0, json_response['stats']['promoted_count']
    assert_equal 1, json_response['stats']['skipped_count']
    assert_match /already been promoted/, json_response['skipped'].first['reason']

    # Verify history entry count is still 1, not duplicated
    @learner1.reload
    assert_equal 1, @learner1.academic_history.size
  end

  test "Test 6 - Missing parameters validation" do
    post "/api/v1/learners/promote", params: { school_id: @school.id.to_s }
    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert json_response['errors'].present?
  end

  test "Test 7 - Non-existent school returns 404" do
    payload = {
      school_id: "non_existent_school_id",
      source_academic_year: "2026",
      destination_academic_year: "2027",
      source_grade_id: @grade6.id.to_s,
      destination_grade_id: @grade7.id.to_s,
      learner_ids: [@learner1.id.to_s]
    }

    post "/api/v1/learners/promote", params: payload
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_match /School not found/, json_response['message']
  end
end
