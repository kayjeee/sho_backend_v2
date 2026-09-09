require "test_helper"

class AssessmentsAndResultsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Victoria College",
      schoolEmail: "victoria@college.org",
      user_email: "admin@victoria.org"
    )
    @grade = Grade.create!(name: "Grade 11", level: 11, school: @school)
    @subject1 = Subject.create!(name: "Maths", school_id: @school.id.to_s)
    @subject2 = Subject.create!(name: "Science", school_id: @school.id.to_s)

    @learner = Learner.create!(
      first_name: "Lindiwe",
      last_name: "Naidoo",
      accession_number: "ACC600",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s
    )

    @ass1 = Assessment.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      subject_id: @subject1.id.to_s,
      academic_year: "2026",
      term: 1,
      name: "Maths Test 1",
      max_score: 100.0
    )

    @ass2 = Assessment.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      subject_id: @subject2.id.to_s,
      academic_year: "2026",
      term: 1,
      name: "Science Test 1",
      max_score: 50.0
    )
  end

  test "POST /api/v1/results/bulk_record records mark sheet and updates on re-submit" do
    post "/api/v1/results/bulk_record", params: {
      school_id: @school.id.to_s,
      assessment_id: @ass1.id.to_s,
      results: [
        { learner_id: @learner.id.to_s, score: 80.0 }
      ]
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 1, json["recorded_count"]
    assert_equal 1, Result.where(assessment_id: @ass1.id.to_s).count

    # Re-submit correction
    post "/api/v1/results/bulk_record", params: {
      school_id: @school.id.to_s,
      assessment_id: @ass1.id.to_s,
      results: [
        { learner_id: @learner.id.to_s, score: 85.0 }
      ]
    }, as: :json

    assert_response :success
    assert_equal 1, Result.where(assessment_id: @ass1.id.to_s).count
    res = Result.find_by(assessment_id: @ass1.id.to_s, learner_id: @learner.id.to_s)
    assert_equal 85.0, res.score
    assert_equal 85.0, res.percentage
  end

  test "GET /api/v1/results/report_card aggregates real learner scores across subjects" do
    # Record scores for both subjects
    Result.create!(assessment_id: @ass1.id.to_s, learner_id: @learner.id.to_s, score: 80.0) # 80/100 = 80%
    Result.create!(assessment_id: @ass2.id.to_s, learner_id: @learner.id.to_s, score: 40.0) # 40/50 = 80%

    get "/api/v1/results/report_card", params: {
      school_id: @school.id.to_s,
      learner_id: @learner.id.to_s,
      academic_year: "2026",
      term: 1
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Lindiwe Naidoo", json["learner_name"]
    assert_equal 80.0, json["overall_average_percentage"]
    assert_equal 2, json["subjects"].size
  end
end
