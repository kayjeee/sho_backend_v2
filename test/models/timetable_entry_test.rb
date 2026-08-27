require "test_helper"

class TimetableEntryTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Oakridge High",
      schoolEmail: "oak@ridge.edu",
      user_email: "admin@oakridge.edu"
    )
    @grade = Grade.create!(name: "Grade 9", level: 9, school: @school)
    @school_class1 = SchoolClass.create!(name: "9A", grade: @grade)
    @school_class2 = SchoolClass.create!(name: "9B", grade: @grade)
    @subject = Subject.create!(name: "Algebra", school_id: @school.id.to_s)
    @teacher = User.create!(
      name: "Mr. Smith",
      email: "smith@oakridge.edu",
      auth0_id: "auth0|smith123"
    )
  end

  test "valid timetable entry creation" do
    entry = TimetableEntry.new(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class1.id.to_s,
      subject_id: @subject.id.to_s,
      teacher_id: @teacher.id.to_s,
      academic_year: "2026",
      day_of_week: 0,
      start_minute: 540,
      end_minute: 585,
      room: "Room 101"
    )

    assert entry.valid?
    assert entry.save
    assert_equal "Monday", entry.day_name
    assert_equal "09:00", entry.start_time_display
    assert_equal "09:45", entry.end_time_display
    assert_equal "9A", entry.class_name
    assert_equal "Algebra", entry.subject_name
    assert_equal "Mr. Smith", entry.teacher_name
  end

  test "rejects class schedule overlap conflict" do
    # 09:00 - 09:45
    TimetableEntry.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class1.id.to_s,
      subject_id: @subject.id.to_s,
      teacher_id: @teacher.id.to_s,
      academic_year: "2026",
      day_of_week: 0,
      start_minute: 540,
      end_minute: 585
    )

    # Overlapping entry for same class 09:30 - 10:15
    overlapping = TimetableEntry.new(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class1.id.to_s,
      subject_id: @subject.id.to_s,
      teacher_id: "other_teacher",
      academic_year: "2026",
      day_of_week: 0,
      start_minute: 570,
      end_minute: 615
    )

    refute overlapping.valid?
    assert overlapping.errors[:base].any? { |e| e.include?("already scheduled 09:00-09:45") }
  end

  test "rejects teacher schedule overlap conflict across different classes" do
    # Teacher booked for Class 9A 09:00 - 09:45
    TimetableEntry.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class1.id.to_s,
      subject_id: @subject.id.to_s,
      teacher_id: @teacher.id.to_s,
      academic_year: "2026",
      day_of_week: 0,
      start_minute: 540,
      end_minute: 585
    )

    # Overlapping entry for SAME teacher in Class 9B 09:15 - 10:00
    teacher_conflict = TimetableEntry.new(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class2.id.to_s,
      subject_id: @subject.id.to_s,
      teacher_id: @teacher.id.to_s,
      academic_year: "2026",
      day_of_week: 0,
      start_minute: 555,
      end_minute: 600
    )

    refute teacher_conflict.valid?
    assert teacher_conflict.errors[:base].any? { |e| e.include?("Mr. Smith already scheduled 09:00-09:45 for 9A on Monday") }
  end

  test "updating an existing entry re-validates against others and not itself" do
    entry = TimetableEntry.create!(
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class1.id.to_s,
      subject_id: @subject.id.to_s,
      teacher_id: @teacher.id.to_s,
      academic_year: "2026",
      day_of_week: 0,
      start_minute: 540,
      end_minute: 585,
      room: "Room 1"
    )

    entry.room = "Room 2"
    assert entry.valid?
    assert entry.save
  end
end
