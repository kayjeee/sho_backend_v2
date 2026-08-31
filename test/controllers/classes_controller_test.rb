require "test_helper"

class ClassesControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "St Marks School",
      schoolEmail: "stmarks@school.org",
      user_email: "admin@stmarks.org"
    )
    @grade = Grade.create!(name: "Grade 10", level: 10, school: @school)
    @school_class = SchoolClass.create!(name: "10A", capacity: 30, grade: @grade)
    @target_class = SchoolClass.create!(name: "10B", capacity: 30, grade: @grade)

    @teacher = User.create!(
      name: "Mr. Dlamini",
      email: "dlamini@stmarks.org",
      auth0_id: "auth0|dlamini123"
    )

    @learner = Learner.create!(
      first_name: "Sipho",
      last_name: "Zuma",
      accession_number: "ACC200",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s
    )
    @school_class.add_learner(@learner.id.to_s)
  end

  test "POST /api/v1/schools/:school_id/grades/:grade_id/classes with name-only payload succeeds and lists created class" do
    post "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/classes", params: {
      name: "Sunshine Room"
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Sunshine Room", json["class"]["name"]
    assert_equal "Grade 10", json["class"]["grade_name"]

    get "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/classes"
    assert_response :success
    index_json = JSON.parse(response.body)
    assert_equal true, index_json["success"]
    class_names = index_json["classes"].map { |c| c["name"] }
    assert_includes class_names, "Sunshine Room"
  end

  test "GET /api/v1/schools/:school_id/grades/:grade_id/classes lists created classes with basic grade_name" do
    get "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/classes"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 2, json["classes"].size
    class_entry = json["classes"].first
    assert_equal "Grade 10", class_entry["grade_name"]
  end

  test "GET /api/v1/schools/:school_id/grades/:grade_id/classes/:id returns detailed class_json with class_teacher_name" do
    @school_class.assign_class_teacher(@teacher.id.to_s)

    get "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/classes/#{@school_class.id}"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    cls = json["class"]
    assert_equal @teacher.id.to_s, cls["class_teacher_id"]
    assert_equal "Mr. Dlamini", cls["class_teacher_name"]
  end

  test "POST assign_teacher assigns class teacher" do
    post "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/classes/#{@school_class.id}/assign_teacher", params: {
      role: "class_teacher",
      teacher_id: @teacher.id.to_s
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Mr. Dlamini", json["class"]["class_teacher_name"]
  end

  test "POST move_learner moves learner between classes" do
    post "/api/v1/schools/#{@school.id}/grades/#{@grade.id}/classes/#{@school_class.id}/move_learner", params: {
      learner_id: @learner.id.to_s,
      target_class_id: @target_class.id.to_s
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal @target_class.id.to_s, @learner.reload.school_class_id.to_s
  end
end
