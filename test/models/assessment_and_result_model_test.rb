require "test_helper"

class AssessmentAndResultModelTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Heritage College",
      schoolEmail: "heritage@college.org",
      user_email: "admin@heritage.org"
    )
    @grade = Grade.create!(name: "Grade 12", level: 12, school: @school)
    @subject = Subject.create!(name: "Accounting", school_id: @school.id.to_s)
    @learner = Learner.create!(
      first_name: "Bongani",
      last_name: "Sithole",
      accession_number: "ACC500",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s
    )
  end

  test "assessment creation and model resolution" do
    ass = Assessment.new(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      subject_id: @subject.id.to_s,
      academic_year: "2026",
      term: 1,
      name: "Mid-Term Exam",
      max_score: 100.0,
      date: Date.today
    )

    assert ass.valid?
    assert ass.save
    assert_equal "Grade 12", ass.grade_name
    assert_equal "Accounting", ass.subject_name
  end

  test "result score validation against max_score" do
    ass = Assessment.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      subject_id: @subject.id.to_s,
      academic_year: "2026",
      term: 1,
      name: "Quiz 1",
      max_score: 50.0
    )

    valid_res = Result.new(
      assessment_id: ass.id.to_s,
      learner_id: @learner.id.to_s,
      score: 45.0
    )
    assert valid_res.valid?
    assert_equal 90.0, valid_res.percentage

    invalid_res = Result.new(
      assessment_id: ass.id.to_s,
      learner_id: @learner.id.to_s,
      score: 55.0
    )
    refute invalid_res.valid?
    assert invalid_res.errors[:score].any? { |e| e.include?("cannot exceed maximum score of 50.0") }
  end
end
