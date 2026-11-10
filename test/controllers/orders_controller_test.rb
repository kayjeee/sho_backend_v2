# frozen_string_literal: true

require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @school = School.create!(schoolName: "Order Controller School #{SecureRandom.hex(4)}", schoolEmail: "order_ctrl_#{SecureRandom.hex(4)}@test.com")
    @other_school = School.create!(schoolName: "Other School #{SecureRandom.hex(4)}", schoolEmail: "other_ctrl_#{SecureRandom.hex(4)}@test.com")

    @admin_user = User.create!(email: "admin_#{SecureRandom.hex(4)}@test.com", auth0_id: "auth0|admin_#{SecureRandom.hex(6)}")
    @parent_user = User.create!(email: "parent_#{SecureRandom.hex(4)}@test.com", auth0_id: "auth0|parent_#{SecureRandom.hex(6)}")
    @other_parent = User.create!(email: "other_p_#{SecureRandom.hex(4)}@test.com", auth0_id: "auth0|other_#{SecureRandom.hex(6)}")

    UserSchoolRole.create!(
      user_id: @admin_user.id,
      school_id: @school.id,
      role: "Admin"
    )

    @learner = Learner.create!(
      firstName: "John",
      lastName: "Doe",
      school_id: @school.id.to_s,
      parent_ids: [ @parent_user.id.to_s ]
    )

    @item = CatalogItem.create!(
      school_id: @school.id.to_s,
      name: "Notebook A4",
      category: "stationery",
      price_cents: 3500,
      stock_quantity: 10,
      is_active: true
    )

    @other_school_item = CatalogItem.create!(
      school_id: @other_school.id.to_s,
      name: "Other School Item",
      category: "stationery",
      price_cents: 2000,
      stock_quantity: 10,
      is_active: true
    )
  end

  def teardown
    Order.where(:school_id.in => [ @school.id.to_s, @other_school.id.to_s ]).destroy_all
    CatalogItem.where(:school_id.in => [ @school.id.to_s, @other_school.id.to_s ]).destroy_all
    Learner.where(id: @learner.id).destroy_all if @learner
    UserSchoolRole.where(:school_id.in => [ @school.id, @other_school.id ]).destroy_all
    @school&.destroy
    @other_school&.destroy
    @admin_user&.destroy
    @parent_user&.destroy
    @other_parent&.destroy
  end

  test "POST /api/v1/orders places order and recomputes prices ignoring client price" do
    post "/api/v1/orders",
         params: {
           auth0_id: @parent_user.auth0_id,
           school_id: @school.id.to_s,
           learner_id: @learner.id.to_s,
           items: [
             {
               catalog_item_id: @item.id.to_s,
               quantity: 2,
               unit_price_cents: 10 # Client tamper attempt! Should be ignored
             }
           ]
         }
    assert_response :created
    json = JSON.parse(response.body)
    assert json["success"]
    order_data = json["data"]
    assert_equal 7000, order_data["subtotal_cents"] # 3500 * 2 = 7000 cents
    assert_equal 3500, order_data["items"].first["unit_price_cents"]

    @item.reload
    assert_equal 8, @item.stock_quantity # 10 - 2 = 8
  end

  test "POST /api/v1/orders rejects items from another school" do
    post "/api/v1/orders",
         params: {
           auth0_id: @parent_user.auth0_id,
           school_id: @school.id.to_s,
           learner_id: @learner.id.to_s,
           items: [
             {
               catalog_item_id: @other_school_item.id.to_s,
               quantity: 1
             }
           ]
         }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_includes json["message"], "does not belong to this school"
  end

  test "POST /api/v1/orders rejects when learner does not belong to parent" do
    post "/api/v1/orders",
         params: {
           auth0_id: @other_parent.auth0_id,
           school_id: @school.id.to_s,
           learner_id: @learner.id.to_s,
           items: [
             {
               catalog_item_id: @item.id.to_s,
               quantity: 1
             }
           ]
         }
    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_includes json["message"], "Learner does not belong to this parent"
  end

  test "POST /api/v1/orders rolls back stock if any item fails" do
    limited_item = CatalogItem.create!(
      school_id: @school.id.to_s,
      name: "Limited Item",
      category: "stationery",
      price_cents: 1000,
      stock_quantity: 1,
      is_active: true
    )

    post "/api/v1/orders",
         params: {
           auth0_id: @parent_user.auth0_id,
           school_id: @school.id.to_s,
           items: [
             { catalog_item_id: @item.id.to_s, quantity: 2 },
             { catalog_item_id: limited_item.id.to_s, quantity: 5 } # Exceeds stock of 1!
           ]
         }
    assert_response :unprocessable_entity

    @item.reload
    assert_equal 10, @item.stock_quantity # Rolled back!

    limited_item.reload
    assert_equal 1, limited_item.stock_quantity
  end

  test "POST /api/v1/orders/:id/cancel cancels placed order and restores stock" do
    post "/api/v1/orders",
         params: {
           auth0_id: @parent_user.auth0_id,
           school_id: @school.id.to_s,
           items: [ { catalog_item_id: @item.id.to_s, quantity: 3 } ]
         }
    assert_response :created
    order_id = JSON.parse(response.body)["data"]["id"]

    @item.reload
    assert_equal 7, @item.stock_quantity

    # Cancel order
    post "/api/v1/orders/#{order_id}/cancel",
         params: { auth0_id: @parent_user.auth0_id }
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "cancelled", json["data"]["status"]

    @item.reload
    assert_equal 10, @item.stock_quantity # Restored!
  end

  test "PATCH /api/v1/orders/:id/status updates status for school admin and enforces transitions" do
    order = Order.create!(
      school_id: @school.id.to_s,
      user_id: @parent_user.id.to_s,
      subtotal_cents: 3500
    )

    # Non-admin attempt
    patch "/api/v1/orders/#{order.id}/status",
          params: { auth0_id: @other_parent.auth0_id, status: "accepted" }
    assert_response :forbidden

    # Admin: placed -> accepted (valid)
    patch "/api/v1/orders/#{order.id}/status",
          params: { auth0_id: @admin_user.auth0_id, status: "accepted" }
    assert_response :ok
    assert_equal "accepted", JSON.parse(response.body)["data"]["status"]

    # Admin: accepted -> completed (invalid transition directly without preparing -> ready)
    patch "/api/v1/orders/#{order.id}/status",
          params: { auth0_id: @admin_user.auth0_id, status: "completed" }
    assert_response :unprocessable_entity
  end

  test "returns 404 for missing order and missing catalog item" do
    get "/api/v1/orders/507f1f77bcf86cd799439011?auth0_id=#{@parent_user.auth0_id}"
    assert_response :not_found

    get "/api/v1/catalog_items/507f1f77bcf86cd799439011?auth0_id=#{@parent_user.auth0_id}"
    assert_response :not_found
  end
end
