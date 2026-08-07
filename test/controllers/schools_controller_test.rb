require 'test_helper'

class SchoolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Mongoid.purge!
  end

  test "POST create handles flat (non-wrapped) JSON payload successfully" do
    payload = {
      schoolName: "Flat secondary school",
      schoolEmail: "flat@school.com",
      country: "South Africa",
      city: "Johannesburg",
      province: "Gauteng",
      theme: "orange",
      adminUsers: [
        {
          name: "Admin User",
          email: "admin@flat.com",
          role: "Admin"
        }
      ]
    }

    post "/api/v1/schools", params: payload
    assert_response :created
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal "Flat secondary school", json_response['data']['school']['schoolName']
    assert_equal "orange", json_response['data']['school']['theme']
    assert_equal "Admin User", json_response['data']['school']['adminUsers'].first['name']
  end

  test "POST create handles standard nested school payload successfully" do
    payload = {
      school: {
        schoolName: "Nested Secondary School",
        schoolEmail: "nested@school.com",
        country: "South Africa",
        city: "Cape Town",
        province: "Western Cape",
        theme: {
          mode: "blue"
        }
      }
    }

    post "/api/v1/schools", params: payload
    assert_response :created
    json_response = JSON.parse(response.body)

    assert json_response['success']
    assert_equal "Nested Secondary School", json_response['data']['school']['schoolName']
    assert_equal "blue", json_response['data']['school']['theme']
  end

  test "GET show school with real ObjectId works successfully" do
    school = School.create!(
      schoolName: "Kagiso High School",
      schoolEmail: "kagiso@school.com"
    )

    get "/api/v1/schools/#{school.id}"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal school.id.to_s, json_response['school']['_id']
  end

  test "GET show school with name slug resolves correctly when exactly one match exists" do
    school = School.create!(
      schoolName: "Kagiso High School",
      schoolEmail: "kagiso@school.com"
    )

    # Resolve by name/slug-like identifier
    get "/api/v1/schools/kagiso-high-school"
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']
    assert_equal school.id.to_s, json_response['school']['_id']
  end

  test "GET show school returns 409 conflict when multiple schools match the identifier" do
    school1 = School.create!(
      schoolName: "Kagiso High School",
      schoolEmail: "kagiso1@school.com"
    )
    school2 = School.new(
      schoolName: "Kagiso High School",
      schoolEmail: "kagiso2@school.com"
    )
    school2.save!(validate: false)

    # Request using the name/slug-like identifier should now result in ambiguity (409)
    get "/api/v1/schools/kagiso-high-school"
    assert_response :conflict
    json_response = JSON.parse(response.body)

    assert_equal false, json_response['success']
    assert_match /Multiple schools match this name/, json_response['message']

    # Check that matching school IDs are returned in response
    assert_not_nil json_response['schools']
    assert_equal 2, json_response['schools'].size
    school_ids = json_response['schools'].map { |s| s['id'] }
    assert_includes school_ids, school1.id.to_s
    assert_includes school_ids, school2.id.to_s
  end

  test "GET show school returns 404 when school is not found" do
    get "/api/v1/schools/non-existent-school"
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']
    assert_equal "School not found", json_response['message']
  end

  test "GET /api/v1/schools/search?q=kagiso returns only id and name of matching schools" do
    school = School.create!(
      schoolName: "Kagiso High School",
      schoolEmail: "kagiso@school.com",
      cash_account: 5000.0,
      adminUsers: [{ name: "Some Admin", email: "admin@k.com" }]
    )

    get "/api/v1/schools/search", params: { q: "kagiso" }
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response['success']

    assert_equal 1, json_response['schools'].size
    matched_school = json_response['schools'].first

    # Assert only id and name are exposed
    assert_equal school.id.to_s, matched_school['id']
    assert_equal "Kagiso High School", matched_school['name']

    # Ensure sensitive fields do NOT exist
    refute_includes matched_school.keys, "cash_account"
    refute_includes matched_school.keys, "payment_history"
    refute_includes matched_school.keys, "adminUsers"
    refute_includes matched_school.keys, "schoolEmail"
  end

  test "GET /api/v1/schools/search?q= returns 400 when query is missing or too short" do
    # Too short
    get "/api/v1/schools/search", params: { q: "k" }
    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal false, json_response['success']

    # Empty
    get "/api/v1/schools/search", params: { q: "" }
    assert_response :bad_request
  end
end
