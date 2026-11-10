# frozen_string_literal: true

require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def setup
    @school = School.create!(schoolName: "Order School #{SecureRandom.hex(4)}", schoolEmail: "order_school_#{SecureRandom.hex(4)}@test.com")
    @user = User.create!(email: "parent_#{SecureRandom.hex(4)}@test.com", auth0_id: "auth0|#{SecureRandom.hex(8)}")
  end

  def teardown
    Order.where(school_id: @school.id.to_s).destroy_all if @school
    @school&.destroy
    @user&.destroy
  end

  test "generates order number before validation on create" do
    order = Order.new(
      school_id: @school.id.to_s,
      user_id: @user.id.to_s,
      fulfilment_method: "collect"
    )
    assert order.valid?
    assert_match(/\ASHO-\d{6}-[A-Z0-9]{4}\z/, order.order_number)
    assert_equal "placed", order.status
    assert_equal "unpaid", order.payment_status
  end

  test "status transitions lifecycle" do
    order = Order.create!(
      school_id: @school.id.to_s,
      user_id: @user.id.to_s
    )

    # placed -> accepted (valid)
    assert order.transition_to!("accepted")
    assert_equal "accepted", order.status

    # accepted -> preparing (valid)
    assert order.transition_to!("preparing")
    assert_equal "preparing", order.status

    # preparing -> ready (valid)
    assert order.transition_to!("ready")
    assert_equal "ready", order.status

    # ready -> completed (valid)
    assert order.transition_to!("completed")
    assert_equal "completed", order.status

    # completed -> cancelled (invalid)
    assert_not order.transition_to!("cancelled")
    assert_equal "completed", order.status
    assert_includes order.errors[:status], "cannot transition from completed to cancelled"
  end

  test "parent cancel only while placed" do
    order = Order.create!(
      school_id: @school.id.to_s,
      user_id: @user.id.to_s
    )

    assert order.cancel_by_parent!(@user.id)
    assert_equal "cancelled", order.status

    order2 = Order.create!(
      school_id: @school.id.to_s,
      user_id: @user.id.to_s
    )
    order2.transition_to!("accepted")
    assert_not order2.cancel_by_parent!(@user.id)
    assert_equal "accepted", order2.status
  end
end
