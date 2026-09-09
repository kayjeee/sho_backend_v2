require "test_helper"

class SupplyRequestModelTest < ActiveSupport::TestCase
  def setup
    Mongoid.purge!
    @school1 = School.create!(
      schoolName: "St Peter High",
      schoolEmail: "stpeter@high.edu",
      user_email: "admin@stpeter.edu"
    )
    @school2 = School.create!(
      schoolName: "St Paul High",
      schoolEmail: "stpaul@high.edu",
      user_email: "admin@stpaul.edu"
    )

    @teacher1 = User.create!(
      name: "Mr. Khumalo",
      email: "khumalo@stpeter.edu",
      auth0_id: "auth0|khumalo1",
      roles: ["teacher"],
      school_ids: [@school1.id.to_s]
    )

    @teacher2 = User.create!(
      name: "Ms. Sithole",
      email: "sithole@stpaul.edu",
      auth0_id: "auth0|sithole2",
      roles: ["teacher"],
      school_ids: [@school2.id.to_s]
    )
  end

  test "valid supply request creation" do
    req = SupplyRequest.new(
      school_id: @school1.id.to_s,
      teacher_id: @teacher1.id.to_s,
      item_type: "paper",
      quantity: 500,
      unit: "pages",
      reason: "Exam printing"
    )

    assert req.valid?
    assert req.save
    assert_equal 0, req.status
    assert_equal "pending", req.status_text
    assert_equal "Mr. Khumalo", req.teacher_name
  end

  test "rejects request if teacher does not belong to school" do
    req = SupplyRequest.new(
      school_id: @school1.id.to_s,
      teacher_id: @teacher2.id.to_s, # Teacher 2 belongs to school2!
      quantity: 100
    )

    refute req.valid?
    assert req.errors[:teacher_id].any? { |e| e.include?("does not belong to target school") }
  end

  test "status transition flow: pending -> approved -> fulfilled" do
    req = SupplyRequest.create!(
      school_id: @school1.id.to_s,
      teacher_id: @teacher1.id.to_s,
      quantity: 250
    )

    # Cannot directly fulfill pending request
    refute req.fulfill!("admin_1")
    assert req.errors[:status].any? { |e| e.include?("cannot transition from pending to fulfilled") }

    # Approve
    assert req.approve!("admin_1", "Approved for term 1")
    assert_equal 1, req.reload.status
    assert_equal "approved", req.status_text

    # Cannot reject approved request
    refute req.reject!("admin_1")
    assert req.errors[:status].any? { |e| e.include?("cannot transition from approved to rejected") }

    # Fulfill
    assert req.fulfill!("admin_1")
    assert_equal 3, req.reload.status
    assert_equal "fulfilled", req.status_text
  end
end
