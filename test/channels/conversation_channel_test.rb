require "test_helper"

class ConversationChannelTest < ActionCable::Channel::TestCase
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "ActionCable Test Academy",
      schoolEmail: "cable@academy.org"
    )
    @user = User.create!(
      name: "Cable User",
      email: "cable@academy.org",
      auth0_id: "auth0|cable123",
      roles: ["parent"]
    )
    @outside_user = User.create!(
      name: "Outside Cable User",
      email: "outside@academy.org",
      auth0_id: "auth0|outside_cable",
      roles: ["parent"]
    )
    @conversation = Conversation.create!(
      school_id: @school.id,
      scope_type: "school",
      participant_ids: [@user.id.to_s],
      title: "Cable Group"
    )
  end

  test "subscribes successfully when user is a conversation participant" do
    stub_connection current_user: @user
    subscribe conversation_id: @conversation.id.to_s

    assert subscription.confirmed?
    assert_has_stream "conversation_#{@conversation.id}"
  end

  test "rejects subscription when user is not a conversation participant" do
    stub_connection current_user: @outside_user
    subscribe conversation_id: @conversation.id.to_s

    assert subscription.rejected?
  end
end