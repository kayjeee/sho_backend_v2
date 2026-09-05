require "test_helper"

class AttendanceRecordTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "St Jude Academy",
      schoolEmail: "stjude@academy.org",
      user_email: "admin@stjude.org"
    )
    @grade = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @school_class = SchoolClass.create!(name: "10A", grade: @grade)
    @learner = Learner.create!(
      first_name: "Thabo",
      last_name: "Mokoena",
      accession_number: "ACC100",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s
    )
  end

  test "valid attendance record creation" do
    record = AttendanceRecord.new(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      learner_id: @learner.id.to_s,
      date: Date.today,
      status: 0,
      recorded_by_id: "teacher_123",
      note: "Present on time"
    )

    assert record.valid?
    assert record.save
    assert_equal "present", record.status_text
    assert_equal "Thabo Mokoena", record.learner_name
  end

  test "validations requirement" do
    record = AttendanceRecord.new
    refute record.valid?
    assert_includes record.errors[:school_id], "can't be blank"
    assert_includes record.errors[:grade_id], "can't be blank"
    assert_includes record.errors[:school_class_id], "can't be blank"
    assert_includes record.errors[:learner_id], "can't be blank"
    assert_includes record.errors[:date], "can't be blank"
    assert_includes record.errors[:status], "can't be blank"
    assert_includes record.errors[:recorded_by_id], "can't be blank"
  end

  test "scopes filtering" do
    today = Date.today
    yesterday = Date.yesterday

    r1 = AttendanceRecord.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      learner_id: @learner.id.to_s,
      date: today,
      status: 0,
      recorded_by_id: "teacher_1"
    )

    learner2 = Learner.create!(
      first_name: "Sipho",
      last_name: "Nkomo",
      accession_number: "ACC101",
      school_id: @school.id.to_s
    )

    r2 = AttendanceRecord.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      learner_id: learner2.id.to_s,
      date: yesterday,
      status: 1,
      recorded_by_id: "teacher_1"
    )

    assert_equal 2, AttendanceRecord.by_school(@school.id.to_s).count
    assert_equal 1, AttendanceRecord.present.count
    assert_equal 1, AttendanceRecord.absent.count
    assert_equal 1, AttendanceRecord.by_learner(@learner.id.to_s).count
    assert_equal 1, AttendanceRecord.by_date_range(today, today).count
  end

  test "to_api_hash resolution" do
    record = AttendanceRecord.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      learner_id: @learner.id.to_s,
      date: Date.today,
      status: 2,
      recorded_by_id: "teacher_99",
      note: "10 mins late"
    )

    hash = record.to_api_hash
    assert_equal record.id.to_s, hash[:id]
    assert_equal @school.id.to_s, hash[:school_id]
    assert_equal @learner.id.to_s, hash[:learner_id]
    assert_equal "Thabo Mokoena", hash[:learner_name]
    assert_equal 2, hash[:status]
    assert_equal "late", hash[:status_text]
    assert_equal "10 mins late", hash[:note]
  end
end
