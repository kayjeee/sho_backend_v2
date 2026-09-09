require "test_helper"

class TermsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Mongoid.purge!
    @school1 = School.create!(
      schoolName: "Zambezi High",
      schoolEmail: "zambezi@high.org",
      user_email: "admin@zambezi.org"
    )
    @school2 = School.create!(
      schoolName: "Limpopo High",
      schoolEmail: "limpopo@high.org",
      user_email: "admin@limpopo.org"
    )

    today = Date.current
    @term1 = Term.create!(
      school_id: @school1.id.to_s,
      academic_year: today.year,
      term_number: 1,
      start_date: today - 10.days,
      end_date: today + 20.days
    )
  end

  test "GET /api/v1/terms requires school_id" do
    get "/api/v1/terms"
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
  end

  test "GET /api/v1/terms lists terms scoped to school" do
    get "/api/v1/terms", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal 1, json["total"]
    assert_equal @term1.id.to_s, json["terms"].first["id"]
  end

  test "POST /api/v1/terms creates term successfully" do
    today = Date.current
    post "/api/v1/terms", params: {
      school_id: @school1.id.to_s,
      term: {
        term_number: 2,
        academic_year: today.year,
        start_date: (today + 30.days).iso8601,
        end_date: (today + 90.days).iso8601
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "Term 2", json["term"]["name"]
  end

  test "GET /api/v1/terms/current returns current term when active" do
    get "/api/v1/terms/current", params: { school_id: @school1.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal @term1.id.to_s, json["current_term"]["id"]
    assert_equal Date.current.year, json["current_academic_year"]
  end

  test "GET /api/v1/terms/current returns null term with sensible fallback year when no terms configured" do
    get "/api/v1/terms/current", params: { school_id: @school2.id.to_s }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_nil json["current_term"]
    assert_equal Date.current.year, json["current_academic_year"]
  end
end
