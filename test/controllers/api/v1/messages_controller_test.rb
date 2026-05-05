require "test_helper"

class Api::V1::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "Test School")
    @user1 = User.create!(email: "user1@example.rb", name: "User 1", roles: ["teacher"])
    @user2 = User.create!(email: "user2@example.rb", name: "User 2", roles: ["parent"])
    @conversation = Conversation.create!(
      participant_ids: [@user1.id.to_s, @user2.id.to_s],
      school_id: @school.id,
      user_id: @user1.id
    )
  end

  test "GET index updates unread messages from other users to delivered" do
    msg = @conversation.messages.create!(
      content: "Hello from User 2",
      sender_id: @user2.id.to_s,
      user_id: @user2.id.to_s,
      status: "sent"
    )

    get api_v1_conversation_messages_url(@conversation),
        headers: { "X-User-Email" => @user1.email },
        as: :json

    assert_response :success
    msg.reload
    assert_equal "delivered", msg.status
  end

  test "PUT read updates unread messages from other users to read" do
    msg = @conversation.messages.create!(
      content: "Hello from User 2",
      sender_id: @user2.id.to_s,
      user_id: @user2.id.to_s,
      status: "delivered"
    )

    put read_api_v1_conversation_url(@conversation),
        headers: { "X-User-Email" => @user1.email },
        as: :json

    assert_response :success
    msg.reload
    assert_equal "read", msg.status
    assert msg.read
  end
end
