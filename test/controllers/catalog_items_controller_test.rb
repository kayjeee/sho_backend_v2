# frozen_string_literal: true

require "test_helper"

class CatalogItemsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @school = School.create!(schoolName: "Shop School #{SecureRandom.hex(4)}", schoolEmail: "shopschool_#{SecureRandom.hex(4)}@test.com")
    @admin_user = User.create!(email: "admin_#{SecureRandom.hex(4)}@test.com", auth0_id: "auth0|admin_#{SecureRandom.hex(6)}")
    @parent_user = User.create!(email: "parent_#{SecureRandom.hex(4)}@test.com", auth0_id: "auth0|parent_#{SecureRandom.hex(6)}")

    # Admin role
    UserSchoolRole.create!(
      user_id: @admin_user.id,
      school_id: @school.id,
      role: "Admin"
    )

    @item = CatalogItem.create!(
      school_id: @school.id.to_s,
      name: "Math Exam 2024",
      category: "print",
      subcategory: "past_exam_paper",
      price_cents: 2500,
      stock_quantity: 10,
      is_active: true
    )
  end

  def teardown
    CatalogItem.where(school_id: @school.id.to_s).destroy_all if @school
    UserSchoolRole.where(school_id: @school.id).destroy_all if @school
    @school&.destroy
    @admin_user&.destroy
    @parent_user&.destroy
  end

  test "GET /api/v1/schools/:school_id/catalog_items lists active items" do
    get "/api/v1/schools/#{@school.id}/catalog_items?auth0_id=#{@parent_user.auth0_id}"
    assert_response :ok
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal 1, json["total"]
    assert_equal "Math Exam 2024", json["data"].first["name"]
    assert_equal 2500, json["data"].first["price_cents"]
  end

  test "GET /api/v1/catalog_items/:id shows item" do
    get "/api/v1/catalog_items/#{@item.id}?auth0_id=#{@parent_user.auth0_id}"
    assert_response :ok
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal @item.id.to_s, json["data"]["id"]
  end

  test "POST /api/v1/schools/:school_id/catalog_items fails for non-admin" do
    post "/api/v1/schools/#{@school.id}/catalog_items",
         params: {
           auth0_id: @parent_user.auth0_id,
           catalog_item: {
             name: "Unauthorized Item",
             category: "stationery",
             price_cents: 1000
           }
         }
    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
  end

  test "POST /api/v1/schools/:school_id/catalog_items succeeds for admin" do
    post "/api/v1/schools/#{@school.id}/catalog_items",
         params: {
           auth0_id: @admin_user.auth0_id,
           catalog_item: {
             name: "School Diary",
             category: "stationery",
             price_cents: 4500,
             stock_quantity: 50
           }
         }
    assert_response :created
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal "School Diary", json["data"]["name"]
    assert_equal 4500, json["data"]["price_cents"]
  end

  test "DELETE /api/v1/catalog_items/:id soft-deletes item for admin" do
    delete "/api/v1/catalog_items/#{@item.id}?auth0_id=#{@admin_user.auth0_id}"
    assert_response :ok
    json = JSON.parse(response.body)
    assert json["success"]
    @item.reload
    assert_equal false, @item.is_active
  end
end
