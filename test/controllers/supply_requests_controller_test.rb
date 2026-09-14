require "test_helper"

class SupplyRequestsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school1 = School.create!(
      schoolName: "Parktown College",
      schoolEmail: "parktown@college.org",
      user_email: "admin@parktown.org"
    )
    @school2 = School.create!(
      schoolName: "Midrand High",
      schoolEmail: "midrand@high.org",
      user_email: "admin@midrand.org"
    )

    @teacher1 = User.create!(
      name: "Mr. Bester",
      email: "bester@parktown.org",
      auth0_id: "auth0|bester1",
      roles: ["teacher"],
      school_ids: [@school1.id.to_s]
    )

    @teacher2 = User.create!(
      name: "Mrs. Adams",
      email: "adams@midrand.org",
      auth0_id: "auth0|adams2",
      roles: ["teacher"],
      school_ids: [@school2.id.to_s]
    )

    @req1 = SupplyRequest.create!(
      school_id: @school1.id.to_s,
      teacher_id: @teacher1.id.to_s,
      item_type: "paper",
      quantity: 500,
      unit: "pages",
      reason: "Term 1 exam paper"
    )
  end

  test "GET /api/v1/supply_requests requires school_id" do
    get "/api/v1/supply_requests"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
  end

  test "GET /api/v1/supply_requests lists requests scoped to school" do
    get "/api/v1/supply_requests", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 1, json["total"]
    assert_equal @req1.id.to_s, json["supply_requests"].first["id"]
    assert_equal "Mr. Bester", json["supply_requests"].first["teacher_name"]
  end

  test "POST /api/v1/supply_requests creates request successfully" do
    post "/api/v1/supply_requests", params: {
      school_id: @school1.id.to_s,
      supply_request: {
        teacher_id: @teacher1.id.to_s,
        quantity: 200,
        reason: "Class quiz copies"
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Mr. Bester", json["supply_request"]["teacher_name"]
    assert_equal 200, json["supply_request"]["quantity"]
  end

  test "POST /api/v1/supply_requests rejects cross-school teacher" do
    post "/api/v1/supply_requests", params: {
      school_id: @school1.id.to_s,
      supply_request: {
        teacher_id: @teacher2.id.to_s, # Teacher 2 belongs to school2
        quantity: 100
      }
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["errors"].any? { |e| e.include?("does not belong to target school") }
  end

  test "PATCH approve, reject, fulfill flow" do
    # Approve
    patch "/api/v1/supply_requests/#{@req1.id}/approve", params: {
      school_id: @school1.id.to_s,
      admin_note: "Approved by Principal"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "approved", json["supply_request"]["status_text"]

    # Fulfill
    patch "/api/v1/supply_requests/#{@req1.id}/fulfill", params: {
      school_id: @school1.id.to_s
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "fulfilled", json["supply_request"]["status_text"]
  end

  test "GET /api/v1/supply_requests/summary aggregates quantities" do
    # Add a fulfilled request
    r2 = SupplyRequest.create!(
      school_id: @school1.id.to_s,
      teacher_id: @teacher1.id.to_s,
      quantity: 300,
      status: 3
    )

    get "/api/v1/supply_requests/summary", params: {
      school_id: @school1.id.to_s,
      teacher_id: @teacher1.id.to_s
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    summary = json["summary"]
    assert_equal 2, summary["total_requests"]
    assert_equal 800, summary["requested_quantity"]
    assert_equal 300, summary["fulfilled_quantity"]
  end
end
