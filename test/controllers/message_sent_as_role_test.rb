require "test_helper"

class MessageSentAsRoleTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!

    @school = School.create!(
      schoolName: "Role Test School",
      schoolEmail: "role@school.org"
    )

    @parent_only = User.create!(
      name: "Parent Only User",
      email: "parent_only@school.org",
      auth0_id: "auth0|parent_only_123",
      roles: ["parent"]
    )

    @multi_role_user = User.create!(
      name: "Multi Role User",
      email: "multirole@school.org",
      auth0_id: "auth0|multirole_123",
      roles: ["parent", "teacher"]
    )

    @conversation = Conversation.create!(
      school_id: @school.id,
      scope_type: "school",
      participant_ids: [@parent_only.id.to_s, @multi_role_user.id.to_s],
      title: "Role Test Group"
    )
  end

  test "single-role parent sending sent_as_role 'parent' succeeds" do
    post "/api/v1/conversations/#{@conversation.id}/messages", params: {
      message: {
        content: "Hello as parent",
        user_id: @parent_only.auth0_id,
        sent_as_role: "parent"
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    msg_data = json["data"]
    assert_equal "parent", msg_data["sent_as_role"]
  end

  test "single-role parent claiming spoofed role 'admin' is rejected with 422" do
    post "/api/v1/conversations/#{@conversation.id}/messages", params: {
      message: {
        content: "Spoofed admin message",
        user_id: @parent_only.auth0_id,
        sent_as_role: "admin"
      }
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/Invalid sent_as_role/i, json["error"])
  end

  test "multi-role user can send as 'parent' or 'teacher', but not 'admin'" do
    # As parent
    post "/api/v1/conversations/#{@conversation.id}/messages", params: {
      message: {
        content: "Sending as parent",
        user_id: @multi_role_user.auth0_id,
        sent_as_role: "parent"
      }
    }, as: :json

    assert_response :created
    json1 = JSON.parse(response.body)
    assert_equal "parent", json1["data"]["sent_as_role"]

    # As teacher
    post "/api/v1/conversations/#{@conversation.id}/messages", params: {
      message: {
        content: "Sending as teacher",
        user_id: @multi_role_user.auth0_id,
        sent_as_role: "teacher"
      }
    }, as: :json

    assert_response :created
    json2 = JSON.parse(response.body)
    assert_equal "teacher", json2["data"]["sent_as_role"]

    # Claiming admin
    post "/api/v1/conversations/#{@conversation.id}/messages", params: {
      message: {
        content: "Sending as admin",
        user_id: @multi_role_user.auth0_id,
        sent_as_role: "admin"
      }
    }, as: :json

    assert_response :unprocessable_entity
    json3 = JSON.parse(response.body)
    assert_equal false, json3["success"]
    assert_match(/Invalid sent_as_role/i, json3["error"])
  end

  test "omitting sent_as_role parameter succeeds with sent_as_role nil" do
    post "/api/v1/conversations/#{@conversation.id}/messages", params: {
      message: {
        content: "Legacy message without sent_as_role",
        user_id: @parent_only.auth0_id
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_nil json["data"]["sent_as_role"]
  end

  test "GET messages index includes sent_as_role in serialized response" do
    m1 = Message.create!(
      conversation: @conversation,
      user: @multi_role_user,
      content: "Parent context msg",
      sent_as_role: "parent"
    )

    m2 = Message.create!(
      conversation: @conversation,
      user: @multi_role_user,
      content: "Teacher context msg",
      sent_as_role: "teacher"
    )

    m3 = Message.create!(
      conversation: @conversation,
      user: @parent_only,
      content: "Legacy msg"
    )

    get "/api/v1/conversations/#{@conversation.id}/messages", params: { user_id: @parent_only.auth0_id }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    msgs = json["data"]

    msg1_json = msgs.find { |m| m["id"] == m1.id.to_s }
    assert_equal "parent", msg1_json["sent_as_role"]

    msg2_json = msgs.find { |m| m["id"] == m2.id.to_s }
    assert_equal "teacher", msg2_json["sent_as_role"]

    msg3_json = msgs.find { |m| m["id"] == m3.id.to_s }
    assert_nil msg3_json["sent_as_role"]
  end
end