require "test_helper"

class ConversationParticipantActionsTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school = School.create!(
      schoolName: "St Marks Academy",
      schoolEmail: "stmarks@school.org"
    )

    @admin = User.create!(
      name: "School Admin",
      email: "admin@stmarks.org",
      auth0_id: "auth0|admin_stmarks",
      roles: ["admin"]
    )
    @admin.school_ids = [@school.id.to_s]
    @admin.save!

    @teacher = User.create!(
      name: "Teacher Joe",
      email: "joe@stmarks.org",
      auth0_id: "auth0|teacher_joe",
      roles: ["teacher"]
    )
    @teacher.school_ids = [@school.id.to_s]
    @teacher.save!

    @parent = User.create!(
      name: "Parent Mary",
      email: "mary@stmarks.org",
      auth0_id: "auth0|parent_mary",
      roles: ["parent"]
    )

    @outside_user = User.create!(
      name: "Stranger",
      email: "stranger@other.org",
      auth0_id: "auth0|stranger",
      roles: ["parent"]
    )

    @conversation = Conversation.create!(
      school_id: @school.id,
      scope_type: "school",
      participant_ids: [@admin.id.to_s, @teacher.id.to_s, @parent.id.to_s],
      title: "Whole School Group"
    )
  end

  test "admin can remove a participant from group conversation" do
    post "/api/v1/conversations/#{@conversation.id}/remove_participant", params: {
      user_id: @admin.auth0_id,
      target_user_id: @parent.id.to_s
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Participant removed successfully", json["message"]

    @conversation.reload
    assert_nil @conversation.participant_ids.find { |id| id == @parent.id.to_s }

    # Verify parent no longer sees conversation in GET /api/v1/conversations?user_id=...
    get "/api/v1/conversations", params: { user_id: @parent.auth0_id }
    assert_response :success
    json_list = JSON.parse(response.body)
    assert_equal 0, json_list["total"]
  end

  test "non-admin attempting remove_participant is rejected with 403 forbidden" do
    post "/api/v1/conversations/#{@conversation.id}/remove_participant", params: {
      user_id: @teacher.auth0_id,
      target_user_id: @parent.id.to_s
    }, as: :json

    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/Forbidden/i, json["error"])

    # Ensure participant was NOT removed
    @conversation.reload
    assert_includes @conversation.participant_ids, @parent.id.to_s
  end

  test "remove_participant rejects target_user who is not a participant" do
    post "/api/v1/conversations/#{@conversation.id}/remove_participant", params: {
      user_id: @admin.auth0_id,
      target_user_id: @outside_user.id.to_s
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/not a participant/i, json["error"])
  end

  test "participant can leave a conversation" do
    post "/api/v1/conversations/#{@conversation.id}/leave", params: {
      user_id: @parent.auth0_id
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Successfully left the conversation", json["message"]

    @conversation.reload
    assert_nil @conversation.participant_ids.find { |id| id == @parent.id.to_s || id == @parent.auth0_id }

    # Verify parent no longer sees conversation in GET /api/v1/conversations?user_id=...
    get "/api/v1/conversations", params: { user_id: @parent.auth0_id }
    assert_response :success
    json_list = JSON.parse(response.body)
    assert_equal 0, json_list["total"]
  end

  test "leave rejects non-participant attempting to leave" do
    post "/api/v1/conversations/#{@conversation.id}/leave", params: {
      user_id: @outside_user.auth0_id
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_match(/not a participant/i, json["error"])
  end
end
