require "test_helper"

class SubjectsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school1 = School.create!(
      schoolName: "Apex School",
      schoolEmail: "apex@school.org",
      user_email: "admin@apex.org"
    )
    @school2 = School.create!(
      schoolName: "Beacon Academy",
      schoolEmail: "beacon@academy.org",
      user_email: "admin@beacon.org"
    )
    @grade1 = Grade.create!(name: "Grade 8", level: 8, school: @school1)
    @grade2 = Grade.create!(name: "Grade 9", level: 9, school: @school1)

    @subject1 = Subject.create!(
      name: "English",
      code: "ENG",
      description: "English Language Arts",
      school_id: @school1.id.to_s,
      grade_ids: [@grade1.id.to_s],
      status: 0
    )
    @subject2 = Subject.create!(
      name: "History",
      code: "HIST",
      school_id: @school1.id.to_s,
      grade_ids: [@grade2.id.to_s],
      status: 1
    )
    @subject_other_school = Subject.create!(
      name: "Geography",
      code: "GEO",
      school_id: @school2.id.to_s,
      status: 0
    )
  end

  test "GET /api/v1/subjects requires school_id" do
    get "/api/v1/subjects"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal "School context identifier is required.", json["error"]
  end

  test "GET /api/v1/subjects lists subjects scoped to school" do
    get "/api/v1/subjects", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 2, json["total"]
    subject_ids = json["subjects"].map { |s| s["id"] }
    assert_includes subject_ids, @subject1.id.to_s
    assert_includes subject_ids, @subject2.id.to_s
    refute_includes subject_ids, @subject_other_school.id.to_s
  end

  test "GET /api/v1/subjects filters by status" do
    get "/api/v1/subjects", params: { school_id: @school1.id.to_s, status: "active" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total"]
    assert_equal @subject1.id.to_s, json["subjects"].first["id"]

    get "/api/v1/subjects", params: { school_id: @school1.id.to_s, status: "inactive" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["total"]
    assert_equal @subject2.id.to_s, json["subjects"].first["id"]
  end

  test "GET /api/v1/subjects/:id shows subject with grade_names resolved" do
    get "/api/v1/subjects/#{@subject1.id}", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    subject_data = json["subject"]
    assert_equal @subject1.id.to_s, subject_data["id"]
    assert_equal "English", subject_data["name"]
    assert_equal "ENG", subject_data["code"]
    assert_equal ["Grade 8"], subject_data["grade_names"]
  end

  test "GET /api/v1/subjects/:id rejects cross-school access" do
    get "/api/v1/subjects/#{@subject1.id}", params: { school_id: @school2.id.to_s }
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal "Subject not found", json["error"]
  end

  test "POST /api/v1/subjects creates subject" do
    post "/api/v1/subjects", params: {
      school_id: @school1.id.to_s,
      subject: {
        name: "Physical Science",
        code: "PHYS",
        description: "Intro to Physics",
        grade_ids: [@grade1.id.to_s, @grade2.id.to_s]
      }
    }
    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    created = json["subject"]
    assert_equal "Physical Science", created["name"]
    assert_equal "PHYS", created["code"]
    assert_equal @school1.id.to_s, created["school_id"]
    assert_equal ["Grade 8", "Grade 9"], created["grade_names"]
  end

  test "PATCH /api/v1/subjects/:id updates subject" do
    patch "/api/v1/subjects/#{@subject1.id}", params: {
      school_id: @school1.id.to_s,
      subject: {
        name: "Advanced English",
        code: "ENG-ADV",
        grade_ids: [@grade1.id.to_s, @grade2.id.to_s]
      }
    }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    updated = json["subject"]
    assert_equal "Advanced English", updated["name"]
    assert_equal "ENG-ADV", updated["code"]
    assert_equal ["Grade 8", "Grade 9"], updated["grade_names"]
  end

  test "DELETE /api/v1/subjects/:id deletes subject" do
    delete "/api/v1/subjects/#{@subject1.id}", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    refute Subject.where(id: @subject1.id).exists?
  end

  test "PATCH /api/v1/subjects/:id/activate and /deactivate" do
    patch "/api/v1/subjects/#{@subject1.id}/deactivate", params: { school_id: @school1.id.to_s }
    assert_response :success
    assert_equal 1, @subject1.reload.status
    assert_equal "inactive", @subject1.status_text

    patch "/api/v1/subjects/#{@subject1.id}/activate", params: { school_id: @school1.id.to_s }
    assert_response :success
    assert_equal 0, @subject1.reload.status
    assert_equal "active", @subject1.status_text
  end
end
