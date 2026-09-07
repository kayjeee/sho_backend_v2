require "test_helper"

class ConversationsAndMessagesControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Zambezi College",
      schoolEmail: "zambezi@college.org",
      user_email: "admin@zambezi.org"
    )
    @admin = User.create!(
      name: "Admin",
      email: "admin@zambezi.org",
      auth0_id: "auth0|adminz",
      roles: ["admin"]
    )
    @parent = User.create!(
      name: "Parent User",
      email: "parent@zambezi.org",
      auth0_id: "auth0|parentz",
      roles: ["parent"]
    )
    @unrelated_user = User.create!(
      name: "Unrelated User",
      email: "other@zambezi.org",
      auth0_id: "auth0|otherz",
      roles: ["parent"]
    )

    @grade = Grade.create!(name: "Grade 8", level: 8, school: @school)
    @school_class = SchoolClass.create!(name: "8A", grade: @grade)

    @learner = Learner.create!(
      first_name: "Learner",
      last_name: "One",
      school_id: @school.id.to_s,
      grade_id: @grade.id.to_s,
      school_class_id: @school_class.id.to_s,
      parent_ids: [@parent.id]
    )
    @school_class.add_learner(@learner.id.to_s)
  end

  test "POST create individual 1:1 conversation preserves existing behavior" do
    post "/api/v1/conversations", params: {
      school_id: @school.id.to_s,
      user_id: @parent.auth0_id
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    conv = json["data"]
    assert_equal "individual", conv["scope_type"]
  end

  test "POST create group conversation resolves participants and sets academic_year and term_id" do
    today = Date.current
    term = Term.create!(
      school_id: @school.id.to_s,
      academic_year: today.year,
      term_number: 1,
      start_date: today - 5.days,
      end_date: today + 20.days
    )

    post "/api/v1/conversations", params: {
      conversation: {
        school_id: @school.id.to_s,
        user_id: @admin.auth0_id,
        scope_type: "class",
        scope_id: @school_class.id.to_s
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    conv = json["data"]
    assert_equal "class", conv["scope_type"]
    assert_equal term.academic_year.to_s, conv["academic_year"]
    assert_equal term.id.to_s, conv["term_id"]
    assert_includes conv["participant_ids"], @parent.id.to_s
  end

  test "unrelated user is forbidden from viewing or messaging in group conversation" do
    conv = Conversation.create!(
      school_id: @school.id,
      user_id: @admin.id,
      scope_type: "class",
      scope_id: @school_class.id.to_s,
      participant_ids: [@admin.id.to_s, @parent.id.to_s]
    )

    # Allowed participant
    get "/api/v1/conversations/#{conv.id}", params: { requesting_user_id: @parent.id.to_s }
    assert_response :success

    # Forbidden unrelated user
    get "/api/v1/conversations/#{conv.id}", params: { requesting_user_id: @unrelated_user.id.to_s }
    assert_response :forbidden

    # Forbidden messaging attempt
    post "/api/v1/conversations/#{conv.id}/messages", params: {
      message: {
        content: "Unauthorized hello",
        user_id: @unrelated_user.id.to_s
      }
    }, as: :json
    assert_response :forbidden
  end
end
