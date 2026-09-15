require "test_helper"

class MessagesControllerIndexTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Messages Test High",
      schoolEmail: "messages@high.org",
      user_email: "admin@messages.org"
    )
    @user1 = User.create!(
      name: "Sender User",
      email: "sender@messages.org",
      auth0_id: "auth0|sender1"
    )
    @user2 = User.create!(
      name: "Receiver User",
      email: "receiver@messages.org",
      auth0_id: "auth0|receiver2"
    )
    @conversation = Conversation.create!(
      school_id: @school.id,
      user_id: @user1.id,
      scope_type: "individual",
      participant_ids: [@user1.id.to_s, @user2.id.to_s]
    )

    @msg1 = Message.create!(
      conversation: @conversation,
      user: @user1,
      content: "Hello from user 1"
    )
    @msg2 = Message.create!(
      conversation: @conversation,
      user: @user2,
      content: "Reply from user 2"
    )
  end

  test "GET /api/v1/conversations/:conversation_id/messages includes resolved sender email and name" do
    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers_for(@user1)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    messages = json["data"]
    assert_equal 2, messages.size

    m1 = messages.find { |m| m["id"] == @msg1.id.to_s }
    assert_equal "Hello from user 1", m1["content"]
    assert_equal @user1.id.to_s, m1["user_id"]
    assert_not_nil m1["sender"]
    assert_equal "sender@messages.org", m1["sender"]["email"]
    assert_equal "Sender User", m1["sender"]["name"]

    m2 = messages.find { |m| m["id"] == @msg2.id.to_s }
    assert_equal "Reply from user 2", m2["content"]
    assert_equal @user2.id.to_s, m2["user_id"]
    assert_not_nil m2["sender"]
    assert_equal "receiver@messages.org", m2["sender"]["email"]
    assert_equal "Receiver User", m2["sender"]["name"]
  end
end