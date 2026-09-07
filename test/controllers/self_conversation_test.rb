require "test_helper"

class SelfConversationTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "Self Conversation High",
      schoolEmail: "self@high.org",
      user_email: "admin@self.org"
    )
    @user = User.create!(
      name: "Admin Self",
      email: "admin@self.org",
      auth0_id: "auth0|self123",
      roles: ["admin"]
    )
  end

  test "Conversation.find_or_create_by_school_and_user creates new conversation without raising DocumentNotFound when missing" do
    assert_nil Conversation.where(school_id: @school.id, user_id: @user.id).first

    conv = Conversation.find_or_create_by_school_and_user(@school.id.to_s, @user.auth0_id)

    assert_not_nil conv
    assert conv.persisted?
    assert_equal @school.id, conv.school_id
    assert_equal @user.id, conv.user_id
    assert_equal "individual", conv.scope_type
  end

  test "POST /api/v1/conversations with scope_type 'self' and auth0_id user_id creates self conversation with 1 participant" do
    post "/api/v1/conversations", params: {
      school_id: @school.id.to_s,
      user_id: @user.auth0_id,
      scope_type: "self"
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    conv = json["data"]
    assert_equal "self", conv["scope_type"]
    assert_equal [@user.id.to_s], conv["participant_ids"]
  end
end
