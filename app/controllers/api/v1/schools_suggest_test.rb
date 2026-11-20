# frozen_string_literal: true

require "test_helper"

class SchoolsSuggestTest < ActionDispatch::IntegrationTest
  SENSITIVE_KEYS = %w[schoolEmail user_id user_email school_created_by cash_account
                      payment_history adminUsers invites].freeze

  def setup
    @tag = SecureRandom.hex(3)
    @far = create_school("FarNorth #{@tag} High", city: "Soweto", province: "Gauteng")
    @fair = create_school("Fairview #{@tag} Academy")
    @contains = create_school("The Far Side #{@tag} School")
    @inactive = create_school("Faraway #{@tag} Closed", status: "inactive")
    @special = create_school("Far (North) #{@tag}")
  end

  def teardown
    School.where(schoolName: /#{@tag}/).destroy_all
  end

  test "blank query returns 200 with empty list" do
    get "/api/v1/schools/suggest?q="
    assert_response :ok
    assert_equal [], JSON.parse(response.body)["schools"]
  end

  test "missing query returns 200 with empty list" do
    get "/api/v1/schools/suggest"
    assert_response :ok
    assert_equal [], JSON.parse(response.body)["schools"]
  end

  test "one character query returns empty list" do
    get "/api/v1/schools/suggest?q=f"
    assert_response :ok
    assert_equal [], JSON.parse(response.body)["schools"]
  end

  test "matches case-insensitively with prefix matches before contains matches" do
    get "/api/v1/schools/suggest?q=far"
    assert_response :ok
    names = names_in(response)
    assert_includes names, @far.schoolName
    assert_includes names, @contains.schoolName
    assert_operator names.index(@far.schoolName), :<, names.index(@contains.schoolName)
  end

  test "query param alias is accepted" do
    get "/api/v1/schools/suggest?query=FarNorth #{@tag}"
    assert_response :ok
    assert_includes names_in(response), @far.schoolName
  end

  test "inactive schools are excluded" do
    get "/api/v1/schools/suggest?q=Faraway #{@tag}"
    assert_response :ok
    assert_empty names_in(response)
  end

  test "regex special characters are escaped" do
    get "/api/v1/schools/suggest", params: { q: "Far (North) #{@tag}" }
    assert_response :ok
    assert_equal [@special.schoolName], names_in(response)

    get "/api/v1/schools/suggest", params: { q: ".*" }
    assert_response :ok
    assert_empty names_in(response)
  end

  test "result is limited to 10" do
    12.times { |i| create_school("Limit #{@tag} #{format('%02d', i)}") }
    get "/api/v1/schools/suggest?q=Limit #{@tag}"
    assert_response :ok
    assert_equal 10, names_in(response).length
  end

  test "response exposes only public fields" do
    get "/api/v1/schools/suggest?q=FarNorth #{@tag}"
    assert_response :ok
    school = JSON.parse(response.body)["schools"].first
    assert_equal %w[city id logo province schoolName], school.keys.sort
    assert_equal @far.id.to_s, school["id"]
    assert_empty(school.keys & SENSITIVE_KEYS)
  end

  test "existing search endpoint is unchanged" do
    get "/api/v1/schools/search?query=#{CGI.escape(@far.schoolName)}"
    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal false, json["isAvailable"]

    get "/api/v1/schools/search?q=Fa"
    assert_response :bad_request
  end

  private

  def create_school(name, status: "active", city: nil, province: nil)
    School.create!(schoolName: name, schoolEmail: "s_#{SecureRandom.hex(5)}@test.com",
                   status: status, city: city, province: province)
  end

  def names_in(resp)
    JSON.parse(resp.body)["schools"].map { |s| s["schoolName"] }
  end
end