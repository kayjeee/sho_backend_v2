require "test_helper"

class UserProfileNameFieldsTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @user = User.create!(
      email: "test.profile@school.org",
      auth0_id: "auth0|profile123",
      name: "Old Display Name"
    )
  end

  test "display_name fallback behavior" do
    # 1. Fallback level 1: first_name is present
    u1 = User.new(email: "a@b.com", name: "Old Name", title: "Dr", first_name: "Jane", surname: "Doe")
    assert_equal "Dr Jane Doe", u1.display_name

    u1_no_title = User.new(email: "a@b.com", name: "Old Name", first_name: "Jane", surname: "Doe")
    assert_equal "Jane Doe", u1_no_title.display_name

    # 2. Fallback level 2: first_name nil, name present
    u2 = User.new(email: "a@b.com", name: "Old Name")
    assert_equal "Old Name", u2.display_name

    # 3. Fallback level 3: first_name nil, name nil, email present
    u3 = User.new(email: "fallback@b.com")
    assert_equal "fallback@b.com", u3.display_name
  end

  test "PATCH /api/v1/users/update_profile updates title, first_name, surname" do
    patch "/api/v1/users/update_profile", params: {
      auth0_id: @user.auth0_id,
      user: {
        title: "Mr",
        first_name: "Sipho",
        surname: "Dlamini"
      }
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]

    @user.reload
    assert_equal "Mr", @user.title
    assert_equal "Sipho", @user.first_name
    assert_equal "Dlamini", @user.surname
    assert_equal "Mr Sipho Dlamini", @user.display_name
  end

  test "PATCH update_profile without new name fields is completely unaffected" do
    patch "/api/v1/users/update_profile", params: {
      auth0_id: @user.auth0_id,
      user: {
        department: "Humanities"
      }
    }, as: :json

    assert_response :success
    @user.reload
    assert_equal "Humanities", @user.department
    assert_nil @user.first_name
    assert_nil @user.surname
    assert_equal "Old Display Name", @user.display_name
  end
end
