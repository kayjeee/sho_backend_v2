require "test_helper"

class AddRoleTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @user = User.create!(
      name: "Parent User",
      email: "parent@role.org",
      auth0_id: "auth0|parent_role",
      roles: ["parent"]
    )
  end

  test "POST /api/v1/users/:id/add_role adds role atomically without removing existing roles" do
    post "/api/v1/users/#{@user.id}/add_role", params: {
      role: "admin"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_includes json["roles"], "parent"
    assert_includes json["roles"], "admin"

    @user.reload
    assert_equal ["parent", "admin"], @user.roles
  end

  test "calling add_role with duplicate role does not create duplicates" do
    post "/api/v1/users/#{@user.id}/add_role", params: {
      role: "parent"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal ["parent"], json["roles"]
    assert_equal 1, @user.reload.roles.size
  end

  test "calling add_role without role parameter returns bad_request" do
    post "/api/v1/users/#{@user.id}/add_role", params: {}, as: :json

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal "Role is required", json["error"]
  end
end
