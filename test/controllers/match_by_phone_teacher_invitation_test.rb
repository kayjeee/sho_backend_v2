require "test_helper"

class MatchByPhoneTeacherInvitationTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Phone Match High",
      schoolEmail: "pm@high.org",
      user_email: "admin@pm.org"
    )
    @sender = User.create!(
      name: "Admin User",
      email: "admin@pm.org",
      auth0_id: "auth0|admin_pm"
    )
    @grade = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @teacher = User.create!(
      name: "Teacher PM",
      email: "teacher@pm.org",
      auth0_id: "auth0|teacher_pm",
      phone_number: "27829998888"
    )
  end

  test "POST /api/v1/invitations/match_by_phone accepts teacher invitation and creates TeacherGradeAssignment" do
    invitation = Invitation.create!(
      school_id: @school.id.to_s,
      sender: @sender,
      recipient_phone_number: "27829998888",
      role: "teacher",
      assigned_grade_ids: [@grade.id.to_s]
    )

    post "/api/v1/invitations/match_by_phone", params: {
      phone_number: "0829998888",
      auth0_id: @teacher.auth0_id,
      school_id: @school.id.to_s
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 1, json["matched_count"]

    # Verify invitation accepted
    assert_equal "accepted", invitation.reload.status

    # Verify TeacherGradeAssignment created
    assignments = TeacherGradeAssignment.where(teacher_id: @teacher.id, grade_id: @grade.id).to_a
    assert_equal 1, assignments.size
    assert_equal 0, assignments.first.status

    # Verify teacher roles array updated
    assert_includes @teacher.reload.roles, "teacher"
  end
end
