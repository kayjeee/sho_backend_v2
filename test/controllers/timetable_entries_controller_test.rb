require "test_helper"

class TimetableEntriesControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school1 = School.create!(
      schoolName: "Westridge High",
      schoolEmail: "west@ridge.edu",
      user_email: "admin@westridge.edu"
    )
    @school2 = School.create!(
      schoolName: "Eastridge High",
      schoolEmail: "east@ridge.edu",
      user_email: "admin@eastridge.edu"
    )

    @grade1 = Grade.create!(name: "Grade 10", level: 10, school: @school1)
    @grade2 = Grade.create!(name: "Grade 10", level: 10, school: @school2)

    @school_class1 = SchoolClass.create!(name: "10A", grade: @grade1)
    @school_class_other = SchoolClass.create!(name: "10B", grade: @grade2)

    @subject1 = Subject.create!(name: "Biology", school_id: @school1.id.to_s)
    @subject_other = Subject.create!(name: "Physics", school_id: @school2.id.to_s)

    @teacher = User.create!(
      name: "Mrs. Davis",
      email: "davis@westridge.edu",
      auth0_id: "auth0|davis456"
    )

    @entry1 = TimetableEntry.create!(
      school_id: @school1.id.to_s,
      grade_id: @grade1.id.to_s,
      school_class_id: @school_class1.id.to_s,
      subject_id: @subject1.id.to_s,
      teacher_id: @teacher.id.to_s,
      academic_year: "2026",
      day_of_week: 1, # Tuesday
      start_minute: 480, # 08:00
      end_minute: 525,  # 08:45
      room: "Lab 1"
    )
  end

  test "GET /api/v1/timetable_entries requires academic_year" do
    get "/api/v1/timetable_entries", params: { school_id: @school1.id.to_s }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal "academic_year parameter is required", json["error"]
  end

  test "GET /api/v1/timetable_entries filters by class and teacher" do
    get "/api/v1/timetable_entries", params: {
      school_id: @school1.id.to_s,
      academic_year: "2026",
      school_class_id: @school_class1.id.to_s
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 1, json["total"]
    assert_equal @entry1.id.to_s, json["timetable_entries"].first["id"]
    assert_equal "Biology", json["timetable_entries"].first["subject_name"]

    get "/api/v1/timetable_entries", params: {
      school_id: @school1.id.to_s,
      academic_year: "2026",
      teacher_id: @teacher.id.to_s
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total"]
  end

  test "POST /api/v1/timetable_entries creates entry successfully" do
    post "/api/v1/timetable_entries", params: {
      school_id: @school1.id.to_s,
      timetable_entry: {
        school_class_id: @school_class1.id.to_s,
        subject_id: @subject1.id.to_s,
        teacher_id: @teacher.id.to_s,
        academic_year: "2026",
        day_of_week: 1,
        start_minute: 530, # 08:50 - 09:35 (no overlap with 08:00-08:45)
        end_minute: 575,
        room: "Lab 2"
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    created = json["timetable_entry"]
    assert_equal "08:50", created["start_time_display"]
    assert_equal "09:35", created["end_time_display"]
  end

  test "POST /api/v1/timetable_entries returns 422 with clear error message on schedule conflict" do
    post "/api/v1/timetable_entries", params: {
      school_id: @school1.id.to_s,
      timetable_entry: {
        school_class_id: @school_class1.id.to_s,
        subject_id: @subject1.id.to_s,
        teacher_id: @teacher.id.to_s,
        academic_year: "2026",
        day_of_week: 1,
        start_minute: 500, # 08:20 - 09:05 (overlaps 08:00-08:45)
        end_minute: 545
      }
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["error"].include?("already scheduled 08:00-08:45")
  end

  test "POST /api/v1/timetable_entries rejects cross-school class" do
    post "/api/v1/timetable_entries", params: {
      school_id: @school1.id.to_s,
      timetable_entry: {
        school_class_id: @school_class_other.id.to_s, # Belongs to school2
        subject_id: @subject1.id.to_s,
        teacher_id: @teacher.id.to_s,
        academic_year: "2026",
        day_of_week: 2,
        start_minute: 600,
        end_minute: 645
      }
    }, as: :json

    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal "School class does not belong to target school", json["error"]
  end

  test "DELETE /api/v1/timetable_entries/:id deletes entry" do
    delete "/api/v1/timetable_entries/#{@entry1.id}", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    refute TimetableEntry.where(id: @entry1.id).exists?
  end
end
