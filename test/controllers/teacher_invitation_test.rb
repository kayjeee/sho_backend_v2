require "test_helper"

class TeacherInvitationTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "St Andrews High",
      schoolEmail: "standrews@school.org",
      user_email: "admin@standrews.org"
    )
    @sender = User.create!(
      name: "Admin User",
      email: "admin@standrews.org",
      auth0_id: "auth0|admin99"
    )
    @grade1 = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @grade2 = Grade.create!(name: "Grade 11", level: 11, school: @school)
    @subject = Subject.create!(name: "Physical Science", school_id: @school.id.to_s)

    @teacher_user = User.create!(
      name: "John Teacher",
      email: "john@standrews.org",
      auth0_id: "auth0|teacher123",
      phone_number: "27821112222"
    )
  end

  test "creates teacher invitation with assigned grades, subjects, and teacher_type" do
    post "/api/v1/invitations", params: {
      phone_number: "27821112222",
      school_id: @school.id.to_s,
      sender: @sender.auth0_id,
      role: "teacher",
      teacher_type: "community",
      assigned_grade_ids: [@grade1.id.to_s, @grade2.id.to_s],
      subject_ids: [@subject.id.to_s]
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    inv = json["invitation"]
    assert_equal "teacher", inv["role"]
    assert_equal "community", inv["teacher_type"]
    assert_equal [@grade1.id.to_s, @grade2.id.to_s], inv["assigned_grade_ids"]
    assert_equal ["Grade 10", "Grade 11"], inv["assigned_grade_names"]
    assert_equal [@subject.id.to_s], inv["subject_ids"]
    assert_equal ["Physical Science"], inv["subject_names"]
  end

  test "accepting teacher invitation creates real TeacherGradeAssignment records and updates roles" do
    invitation = Invitation.create!(
      school_id: @school.id.to_s,
      sender: @sender,
      recipient_phone_number: "27821112222",
      role: "teacher",
      teacher_type: "staff",
      assigned_grade_ids: [@grade1.id.to_s, @grade2.id.to_s],
      subject_ids: [@subject.id.to_s]
    )

    post "/api/v1/invitations/verify", params: {
      token: invitation.token,
      auth0_id: @teacher_user.auth0_id
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]

    # Verify TeacherGradeAssignment documents created
    assignments = TeacherGradeAssignment.where(teacher_id: @teacher_user.id).to_a
    assert_equal 2, assignments.size
    assigned_grade_ids = assignments.map { |a| a.grade_id.to_s }
    assert_includes assigned_grade_ids, @grade1.id.to_s
    assert_includes assigned_grade_ids, @grade2.id.to_s

    # Verify user roles updated
    assert_includes @teacher_user.reload.roles, "teacher"
  end

  test "GET /api/v1/invitations with role=teacher filters correctly" do
    Invitation.create!(
      school_id: @school.id.to_s,
      sender: @sender,
      recipient_phone_number: "27823334444",
      role: "parent"
    )
    t_inv = Invitation.create!(
      school_id: @school.id.to_s,
      sender: @sender,
      recipient_phone_number: "27825556666",
      role: "teacher",
      assigned_grade_ids: [@grade1.id.to_s]
    )

    get "/api/v1/invitations", params: {
      school_id: @school.id.to_s,
      role: "teacher"
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 1, json["total"]
    assert_equal t_inv.id.to_s, json["invitations"].first["id"]
    assert_equal ["Grade 10"], json["invitations"].first["assigned_grade_names"]
  end
end
