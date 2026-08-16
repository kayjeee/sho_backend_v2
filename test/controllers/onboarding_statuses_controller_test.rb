require 'test_helper'
require 'cgi'

class OnboardingStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Mongoid.purge!

    @school = School.create!(
      schoolName: "Far North Secondary School",
      schoolEmail: "info@farnorth.com"
    )

    @user = User.create!(
      name: "Kagiso Parent",
      email: "kagiso2025@gmail.com",
      auth0_id: "auth0|6929ae9fecac72d4fcc8424d",
      roles: ["default_role", "parent"]
    )
    @user.schools << @school
    @user.save!
  end

  test "GET show returns user and onboarding fields" do
    get "/api/v1/users/#{CGI.escape(@user.auth0_id)}"
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    user_json = json_response['data']['user']
    assert_equal "Far North Secondary School", user_json['primarySchoolName']
    assert_equal "Far North Secondary School", user_json['schoolName']
    assert_equal false, user_json['onboarding_completed']
    assert_equal false, user_json['onboardingCompleted']
  end

  test "GET onboarding status nested show returns custom fields" do
    get "/api/v1/users/#{CGI.escape(@user.auth0_id)}/onboarding_status"
    assert_response :success
    json_response = JSON.parse(response.body)

    assert json_response['success']
    status_json = json_response['data']
    assert_equal "Far North Secondary School", status_json['primarySchoolName']
    assert_equal "Far North Secondary School", status_json['schoolName']
    assert_equal false, status_json['onboardingCompleted']
    assert_equal 8, status_json['totalStepsCount']
  end

  test "POST complete_step endpoint is role-aware and supports camelCase params" do
    # Complete parent profile_setup
    post "/api/v1/users/#{CGI.escape(@user.auth0_id)}/onboarding_status/complete_step", params: {
      stepName: "profile_setup"
    }
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 12.5, json_response['data']['completionPercentage']
  end
end
