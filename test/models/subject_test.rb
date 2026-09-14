require "test_helper"

class SubjectTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Test High",
      schoolEmail: "test@high.edu",
      user_email: "admin@high.edu"
    )
    @grade1 = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @grade2 = Grade.create!(name: "Grade 11", level: 11, school: @school)
  end

  test "valid subject creation" do
    subject = Subject.new(
      name: "Mathematics",
      code: "MATH",
      description: "Core Math",
      school_id: @school.id.to_s,
      grade_ids: [@grade1.id.to_s, @grade2.id.to_s],
      status: 0
    )

    assert subject.valid?
    assert subject.save
    assert_equal "Mathematics", subject.name
    assert_equal "MATH", subject.code
    assert_equal 0, subject.status
    assert_equal "active", subject.status_text
  end

  test "validations requirement and uniqueness per school" do
    invalid_subject = Subject.new(code: "MATH")
    refute invalid_subject.valid?
    assert_includes invalid_subject.errors[:name], "can't be blank"
    assert_includes invalid_subject.errors[:school_id], "can't be blank"

    Subject.create!(name: "Physics", school_id: @school.id.to_s)
    duplicate = Subject.new(name: "physics", school_id: @school.id.to_s)
    refute duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"

    # Same name for different school is allowed
    other_school = School.create!(schoolName: "Other High", schoolEmail: "other@high.edu", user_email: "other@high.edu")
    other_subject = Subject.new(name: "Physics", school_id: other_school.id.to_s)
    assert other_subject.valid?
  end

  test "scopes by_school, active, inactive" do
    s1 = Subject.create!(name: "Math", school_id: @school.id.to_s, status: 0)
    s2 = Subject.create!(name: "Science", school_id: @school.id.to_s, status: 1)

    other_school = School.create!(schoolName: "Other High", schoolEmail: "other@high.edu", user_email: "other@high.edu")
    s3 = Subject.create!(name: "Art", school_id: other_school.id.to_s, status: 0)

    assert_equal 2, Subject.by_school(@school.id.to_s).count
    assert_includes Subject.by_school(@school.id.to_s), s1
    assert_includes Subject.by_school(@school.id.to_s), s2

    assert_equal 2, Subject.active.count
    assert_includes Subject.active, s1
    assert_includes Subject.active, s3

    assert_equal 1, Subject.inactive.count
    assert_includes Subject.inactive, s2
  end

  test "activate! and deactivate! methods" do
    subject = Subject.create!(name: "Biology", school_id: @school.id.to_s, status: 0)
    assert subject.active?

    subject.deactivate!
    assert subject.inactive?
    assert_equal 1, subject.status
    assert_equal "inactive", subject.status_text

    subject.activate!
    assert subject.active?
    assert_equal 0, subject.status
    assert_equal "active", subject.status_text
  end

  test "grade_names resolution and to_api_hash" do
    subject = Subject.create!(
      name: "Chemistry",
      code: "CHEM",
      description: "Basic Chemistry",
      school_id: @school.id.to_s,
      grade_ids: [@grade1.id.to_s, @grade2.id.to_s]
    )

    expected_names = ["Grade 10", "Grade 11"]
    assert_equal expected_names, subject.grade_names

    hash = subject.to_api_hash
    assert_equal subject.id.to_s, hash[:id]
    assert_equal "Chemistry", hash[:name]
    assert_equal "CHEM", hash[:code]
    assert_equal "Basic Chemistry", hash[:description]
    assert_equal 0, hash[:status]
    assert_equal "active", hash[:status_text]
    assert_equal @school.id.to_s, hash[:school_id]
    assert_equal [@grade1.id.to_s, @grade2.id.to_s], hash[:grade_ids]
    assert_equal expected_names, hash[:grade_names]
  end
end
