require "test_helper"

class UserDepartmentPositionTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @user = User.create!(
      name: "Alice Smith",
      email: "alice@school.org",
      auth0_id: "auth0|alice123",
      roles: ["teacher"]
    )
  end

  test "department and position fields save and serialize in to_api_hash" do
    @user.update!(
      department: "Sciences",
      position: "Head of Department"
    )

    hash = @user.reload.to_api_hash
    assert_equal "Sciences", hash[:department]
    assert_equal "Head of Department", hash[:position]
  end
end
