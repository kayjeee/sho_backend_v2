require "test_helper"

class TeacherGradeAssignmentsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Apex High School",
      schoolEmail: "apex@high.org",
      user_email: "admin@high.org"
    )
    @admin = User.create!(
      name: "Admin User",
      email: "admin@high.org",
      auth0_id: "auth0|admin"
    )
    @teacher = User.create!(
      name: "Mr. Pillay",
      email: "pilly@high.org",
      auth0_id: "auth0|pillay1",
      roles: ["teacher"]
    )
    @grade1 = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @grade2 = Grade.create!(name: "Grade 11", level: 11, school: @school)
  end

  test "POST create assignment and re-posting reactivates without duplicating" do
    post "/api/v1/teacher_grade_assignments", params: {
      school_id: @school.id.to_s,
      teacher_id: @teacher.id.to_s,
      grade_id: @grade1.id.to_s,
      role_type: "primary"
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assignment_id = json["teacher_grade_assignment"]["id"]

    # Deactivate the assignment
    patch "/api/v1/teacher_grade_assignments/#{assignment_id}/deactivate"
    assert_response :success
    assert_equal 1, TeacherGradeAssignment.find(assignment_id).status

    # Re-post same assignment
    post "/api/v1/teacher_grade_assignments", params: {
      school_id: @school.id.to_s,
      teacher_id: @teacher.id.to_s,
      grade_id: @grade1.id.to_s,
      role_type: "primary"
    }, as: :json

    assert_response :success
    # Must reactivate existing, not create duplicate
    assert_equal 1, TeacherGradeAssignment.where(teacher_id: @teacher.id, grade_id: @grade1.id).count
    assert_equal 0, TeacherGradeAssignment.find(assignment_id).status
  end

  test "PATCH terminate and suspend member actions" do
    assignment = TeacherGradeAssignment.create!(
      teacher_id: @teacher.id.to_s,
      grade_id: @grade1.id.to_s,
      school_id: @school.id.to_s,
      assigned_by_id: @admin.id.to_s
    )

    patch "/api/v1/teacher_grade_assignments/#{assignment.id}/terminate", params: { reason: "Resigned" }
    assert_response :success
    assert_equal 2, assignment.reload.status
    assert_equal "terminated", assignment.status_text

    patch "/api/v1/teacher_grade_assignments/#{assignment.id}/suspend", params: { reason: "Under review" }
    assert_response :success
    assert_equal 3, assignment.reload.status
    assert_equal "suspended", assignment.status_text
  end

  test "GET collection routes by_teacher, by_grade, by_school" do
    assignment = TeacherGradeAssignment.create!(
      teacher_id: @teacher.id.to_s,
      grade_id: @grade1.id.to_s,
      school_id: @school.id.to_s,
      assigned_by_id: @admin.id.to_s
    )

    get "/api/v1/teacher_grade_assignments/by_teacher/#{@teacher.id}"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total"]
    assert_equal "Grade 10", json["teacher_grade_assignments"].first["grade"]["name"]

    get "/api/v1/teacher_grade_assignments/by_grade/#{@grade1.id}"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total"]

    get "/api/v1/teacher_grade_assignments/by_school/#{@school.id}"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total"]
  end
end
