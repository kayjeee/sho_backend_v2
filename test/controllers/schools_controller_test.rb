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
end
