require "test_helper"

class AttendanceControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school1 = School.create!(
      schoolName: "Summit High",
      schoolEmail: "summit@high.edu",
      user_email: "admin@summit.edu"
    )
    @school2 = School.create!(
      schoolName: "Valley High",
      schoolEmail: "valley@high.edu",
      user_email: "admin@valley.edu"
    )

    @grade1 = Grade.create!(name: "Grade 11", level: 11, school: @school1)
    @grade_other = Grade.create!(name: "Grade 11", level: 11, school: @school2)

    @school_class1 = SchoolClass.create!(name: "11A", grade: @grade1)
    @school_class_other = SchoolClass.create!(name: "11B", grade: @grade_other)

    @learner1 = Learner.create!(
      first_name: "Lesedi",
      last_name: "Khumalo",
      accession_number: "L101",
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s
    )
    @learner2 = Learner.create!(
      first_name: "Kagiso",
      last_name: "Molefe",
      accession_number: "L102",
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s
    )

    @school_class1.update(learner_ids: [@learner1.id.to_s, @learner2.id.to_s])
  end

  test "POST /api/v1/attendance/bulk_mark marks register and re-marking updates without duplicating" do
    today_str = Date.today.iso8601

    # First marking: learner1 present, learner2 absent
    post "/api/v1/attendance/bulk_mark", params: {
      school_id: @school1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      date: today_str,
      recorded_by_id: "teacher_abc",
      records: [
        { learner_id: @learner1.id.to_s, status: "present" },
        { learner_id: @learner2.id.to_s, status: "absent", note: "Sick leave" }
      ]
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 2, json["marked_count"]
    assert_equal 2, AttendanceRecord.where(school_class_id: @school_class1.id.to_s, date: Date.today).count

    # Second marking (re-marking same day): learner2 marked present now
    post "/api/v1/attendance/bulk_mark", params: {
      school_id: @school1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      date: today_str,
      recorded_by_id: "teacher_abc",
      records: [
        { learner_id: @learner2.id.to_s, status: "present", note: "Arrived late with note" }
      ]
    }, as: :json

    assert_response :success
    # Total count for class and date MUST still be 2 (no duplicate document created)
    assert_equal 2, AttendanceRecord.where(school_class_id: @school_class1.id.to_s, date: Date.today).count

    rec2 = AttendanceRecord.find_by(school_class_id: @school_class1.id.to_s, learner_id: @learner2.id.to_s, date: Date.today)
    assert_equal 0, rec2.status
    assert_equal "present", rec2.status_text
    assert_equal "Arrived late with note", rec2.note
  end

  test "POST /api/v1/attendance/bulk_mark rejects cross-school attempt" do
    post "/api/v1/attendance/bulk_mark", params: {
      school_id: @school1.id.to_s,
      school_class_id: @school_class_other.id.to_s, # Class belongs to school2!
      date: Date.today.iso8601,
      records: [
        { learner_id: @learner1.id.to_s, status: "present" }
      ]
    }, as: :json

    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal "School class does not belong to target school", json["error"]
  end

  test "GET /api/v1/attendance/register returns roster showing unmarked vs marked" do
    today_str = Date.today.iso8601

    # Mark learner1 as present, leave learner2 unmarked
    AttendanceRecord.create!(
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      learner_id: @learner1.id.to_s,
      date: Date.today,
      status: 0,
      recorded_by_id: "teacher_abc"
    )

    get "/api/v1/attendance/register", params: {
      school_id: @school1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      date: today_str
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "11A", json["class_name"]
    assert_equal "Grade 11", json["grade_name"]

    roster = json["roster"]
    assert_equal 2, roster.size

    l1_entry = roster.find { |r| r["learner_id"] == @learner1.id.to_s }
    assert_equal "Lesedi Khumalo", l1_entry["learner_name"]
    assert_equal "present", l1_entry["status"]

    l2_entry = roster.find { |r| r["learner_id"] == @learner2.id.to_s }
    assert_equal "Kagiso Molefe", l2_entry["learner_name"]
    assert_equal "unmarked", l2_entry["status"]
  end

  test "GET /api/v1/attendance/summary calculates accurate counts" do
    today = Date.today
    yesterday = Date.yesterday

    AttendanceRecord.create!(
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      learner_id: @learner1.id.to_s,
      date: today,
      status: 0,
      recorded_by_id: "teacher_abc"
    )
    AttendanceRecord.create!(
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      learner_id: @learner2.id.to_s,
      date: today,
      status: 1,
      recorded_by_id: "teacher_abc"
    )
    AttendanceRecord.create!(
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      learner_id: @learner1.id.to_s,
      date: yesterday,
      status: 2,
      recorded_by_id: "teacher_abc"
    )

    # Whole school summary over range
    get "/api/v1/attendance/summary", params: {
      school_id: @school1.id.to_s,
      from: yesterday.iso8601,
      to: today.iso8601
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 3, json["total_records"]
    assert_equal 1, json["summary"]["present"]
    assert_equal 1, json["summary"]["absent"]
    assert_equal 1, json["summary"]["late"]
    assert_equal 0, json["summary"]["excused"]

    # Single learner summary
    get "/api/v1/attendance/summary", params: {
      school_id: @school1.id.to_s,
      learner_id: @learner1.id.to_s
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 2, json["total_records"]
    assert_equal 1, json["summary"]["present"]
    assert_equal 1, json["summary"]["late"]
    assert_equal 0, json["summary"]["absent"]
  end
end
