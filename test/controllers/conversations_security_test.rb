require "test_helper"

class ConversationsSecurityTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!

    @school = School.create!(
      schoolName: "Security Test Academy",
      schoolEmail: "sec@academy.org",
      user_email: "admin@sec.org"
    )

    @school_b = School.create!(
      schoolName: "Foreign School B",
      schoolEmail: "info@schoolb.org",
      user_email: "admin@schoolb.org"
    )

    @admin = User.create!(
      name: "Admin User",
      email: "admin@sec.org",
      auth0_id: "auth0|admin_sec",
      roles: ["admin"],
      school_ids: [@school.id.to_s]
    )

    @parent_a = User.create!(
      name: "Parent A",
      email: "parenta@sec.org",
      auth0_id: "auth0|parent_a",
      roles: ["parent"]
    )

    @parent_b = User.create!(
      name: "Parent B",
      email: "parentb@sec.org",
      auth0_id: "auth0|parent_b",
      roles: ["parent"]
    )

    @outside_user = User.create!(
      name: "Outside User",
      email: "outside@sec.org",
      auth0_id: "auth0|outside",
      roles: ["parent"]
    )

    # Private conversation between Parent B and Admin
    @conv_b = Conversation.create!(
      school_id: @school.id,
      user_id: @parent_b.id,
      scope_type: "individual",
      participant_ids: [@parent_b.id.to_s, @admin.id.to_s]
    )

    @msg_b = Message.create!(
      conversation: @conv_b,
      user: @parent_b,
      content: "Parent B private message"
    )
  end

  test "1. Parent A cannot read Parent B's conversations by supplying Parent B's user_id param" do
    # Parent A tries to query index passing Parent B's user_id in params
    get "/api/v1/conversations", params: { user_id: @parent_b.id.to_s, userId: @parent_b.auth0_id }, headers: auth_headers_for(@parent_a)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    # Parent A has no conversations, so result total must be 0 despite passing Parent B's user_id
    assert_equal 0, json["total"]
    assert_equal [], json["data"]

    # Parent A tries to GET Parent B's conversation directly
    get "/api/v1/conversations/#{@conv_b.id}", params: { requesting_user_id: @parent_b.id.to_s }, headers: auth_headers_for(@parent_a)

    assert_response :forbidden
    json_show = JSON.parse(response.body)
    assert_equal false, json_show["success"]
    assert_match(/Forbidden/i, json_show["error"])
  end

  test "2. Removed or left participant no longer appears in index results even if they were original creator" do
    # Group conversation created by Parent A
    group_conv = Conversation.create!(
      school_id: @school.id,
      user_id: @parent_a.id, # Parent A is original creator/owner
      scope_type: "school",
      participant_ids: [@parent_a.id.to_s, @parent_b.id.to_s, @admin.id.to_s],
      title: "Community Group"
    )

    # Parent A sees it initially
    get "/api/v1/conversations", headers: auth_headers_for(@parent_a)
    assert_response :success
    json_before = JSON.parse(response.body)
    assert_equal 1, json_before["total"]

    # Parent A leaves the group conversation
    post "/api/v1/conversations/#{group_conv.id}/leave", headers: auth_headers_for(@parent_a), as: :json
    assert_response :success

    # Parent A queries index again -> conversation MUST NOT appear even though Parent A was creator (user_id)
    get "/api/v1/conversations", headers: auth_headers_for(@parent_a)
    assert_response :success
    json_after = JSON.parse(response.body)
    assert_equal 0, json_after["total"]
  end

  test "3. Non-participant cannot read messages or post messages in conversation they don't belong to" do
    # Parent A tries to read messages in Parent B's conversation
    get "/api/v1/conversations/#{@conv_b.id}/messages", params: { requesting_user_id: @parent_b.id.to_s }, headers: auth_headers_for(@parent_a)

    assert_response :forbidden
    json_read = JSON.parse(response.body)
    assert_equal false, json_read["success"]
    assert_match(/Forbidden/i, json_read["error"])

    # Parent A tries to post a message in Parent B's conversation
    post "/api/v1/conversations/#{@conv_b.id}/messages", params: {
      message: {
        content: "Malicious post",
        user_id: @parent_b.id.to_s
      }
    }, headers: auth_headers_for(@parent_a), as: :json

    assert_response :forbidden
    json_post = JSON.parse(response.body)
    assert_equal false, json_post["success"]
    assert_match(/Forbidden/i, json_post["error"])
  end

  test "4. remove_participant rejects non-admin requester regardless of admin-looking params" do
    group_conv = Conversation.create!(
      school_id: @school.id,
      scope_type: "school",
      participant_ids: [@parent_a.id.to_s, @parent_b.id.to_s, @admin.id.to_s],
      title: "School Group"
    )

    # Parent A attempts remove_participant supplying Admin's user_id/auth0_id in body/query params
    post "/api/v1/conversations/#{group_conv.id}/remove_participant", params: {
      user_id: @admin.auth0_id,
      requester_id: @admin.id.to_s,
      target_user_id: @parent_b.id.to_s
    }, headers: auth_headers_for(@parent_a), as: :json

    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/Forbidden: Requester is not an admin/i, json["error"])

    # Target user (Parent B) remains in group
    group_conv.reload
    assert_includes group_conv.participant_ids, @parent_b.id.to_s
  end

  test "5. Message sender is always the authenticated user regardless of body content" do
    # Group conversation with Parent A and Parent B
    group_conv = Conversation.create!(
      school_id: @school.id,
      scope_type: "school",
      participant_ids: [@parent_a.id.to_s, @parent_b.id.to_s],
      title: "Shared Group"
    )

    # Parent A posts a message attempting to spoof Parent B's user_id in the body
    post "/api/v1/conversations/#{group_conv.id}/messages", params: {
      message: {
        content: "Impersonated message",
        user_id: @parent_b.id.to_s
      }
    }, headers: auth_headers_for(@parent_a), as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]

    # Verify saved message user_id is Parent A, NOT Parent B
    posted_msg = Message.find(json["data"]["_id"] || json["data"]["id"])
    assert_equal @parent_a.id.to_s, posted_msg.user_id.to_s
  end

  test "6. Requests without valid Authorization token are rejected with 401 Unauthorized" do
    get "/api/v1/conversations"
    assert_response :unauthorized

    get "/api/v1/conversations/#{@conv_b.id}"
    assert_response :unauthorized

    get "/api/v1/conversations/#{@conv_b.id}/messages"
    assert_response :unauthorized

    post "/api/v1/conversations/#{@conv_b.id}/leave"
    assert_response :unauthorized
  end

  test "7. Cross-school class or grade conversation creation rejects entity from foreign school" do
    # Create Grade and Class for foreign School B
    grade_b = Grade.create!(name: "Grade 10 Foreign", level: 10, school: @school_b)
    class_b = SchoolClass.create!(name: "10B Foreign", grade: grade_b)

    learner_foreign = Learner.create!(
      first_name: "Foreign",
      last_name: "Learner",
      school_id: @school_b.id.to_s,
      grade_id: grade_b.id.to_s,
      school_class_id: class_b.id.to_s,
      parent_ids: [@parent_a.id]
    )
    class_b.add_learner(learner_foreign.id.to_s)

    # Admin attempts to create group conversation for School A passing foreign class_b
    post "/api/v1/conversations", params: {
      conversation: {
        school_id: @school.id.to_s,
        scope_type: "class",
        scope_id: class_b.id.to_s
      }
    }, headers: auth_headers_for(@admin), as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    # Because class_b belongs to School B, no learners from School A match -> only requesting admin is in participant_ids
    assert_equal [@admin.id.to_s], json["data"]["participant_ids"]
  end

  test "8. Conversation response includes explicit serialized participants with resolved display names" do
    get "/api/v1/conversations/#{@conv_b.id}", headers: auth_headers_for(@parent_b)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    participants = json["data"]["participants"]
    assert_not_nil participants
    assert_equal 2, participants.size

    p_b = participants.find { |p| p["id"] == @parent_b.id.to_s }
    assert_not_nil p_b
    assert_equal @parent_b.auth0_id, p_b["auth0_id"]
    assert_equal "Parent B", p_b["name"]
    assert_equal "parentb@sec.org", p_b["email"]
  end
end