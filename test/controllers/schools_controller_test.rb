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
end
