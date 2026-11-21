require "test_helper"

class MyLearnersControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!

    @school = School.create!(
      schoolName: "Zambezi Primary School",
      schoolEmail: "zambezi@primary.org"
    )

    @parent = User.create!(
      name: "Parent User",
      email: "parent@zambezi.org",
      auth0_id: "auth0|parent_zambezi_123",
      roles: ["parent"]
    )

    @grade = Grade.create!(name: "Grade 3", level: 3, school: @school)

    @learner1 = Learner.create!(
      first_name: "Chipo",
      last_name: "Moyo",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      parent_ids: [@parent.id]
    )

    @learner2 = Learner.create!(
      first_name: "Tendai",
      last_name: "Moyo",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      parent_ids: [@parent.id.to_s]
    )
  end

  test "GET /api/v1/parents/my_learners returns linked learners for parent" do
    get "/api/v1/parents/my_learners", params: { auth0_id: @parent.auth0_id }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 2, json["total"]
    learners = json["learners"]
    assert_equal 2, learners.size

    names = learners.map { |l| l["firstName"] || l["first_name"] }
    assert_includes names, "Chipo"
    assert_includes names, "Tendai"
  end

  test "GET /api/v1/parents/my_learners returns 400 when auth0_id parameter is missing" do
    get "/api/v1/parents/my_learners"

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/Missing required parameter/i, json["error"])
  end

  test "GET /api/v1/parents/my_learners returns 404 when user is not found" do
    get "/api/v1/parents/my_learners", params: { auth0_id: "auth0|nonexistent_user" }

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/User not found/i, json["error"])
  end

  test "GET /api/v1/parents/profile returns user profile data" do
    get "/api/v1/parents/profile", params: { auth0_id: @parent.auth0_id }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal @parent.auth0_id, json["data"]["auth0_id"]
  end
end