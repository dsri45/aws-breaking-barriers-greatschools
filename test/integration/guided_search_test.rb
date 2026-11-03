require "test_helper"

class GuidedSearchTest < ActionDispatch::IntegrationTest
  test "a search, its evidence and shortlist persist only in the same browser session" do
    token = open_search_session
    post "/api/search", params: { message: "STEM in Woodstock" }, as: :json,
      headers: { "X-CSRF-Token" => token }
    assert_response :success
    result = response.parsed_body.fetch("results").first
    assert_equal "confirmed", result.fetch("evidence").first.fetch("status")
    school_id = result.fetch("id")

    assert_difference("ShortlistEntry.count", 1) do
      post "/api/shortlist", params: { school_id: school_id }, as: :json,
        headers: { "X-CSRF-Token" => token }
    end
    assert_response :created

    assert_no_difference("ShortlistEntry.count") do
      post "/api/shortlist", params: { school_id: school_id }, as: :json,
        headers: { "X-CSRF-Token" => token }
    end
    assert_response :ok

    get "/api/session"
    assert_equal ["user", "assistant"], response.parsed_body.fetch("history").pluck("role")
    assert_equal({ "query" => "STEM in Woodstock" }, response.parsed_body.fetch("preferences"))
    assert_equal [result], response.parsed_body.fetch("shortlist")

    other_browser = open_session
    other_browser.get "/api/session"
    assert_empty other_browser.response.parsed_body.fetch("history")
    assert_empty other_browser.response.parsed_body.fetch("shortlist")

    delete "/api/shortlist/#{school_id}", headers: { "X-CSRF-Token" => token }
    assert_response :no_content
    get "/api/session"
    assert_empty response.parsed_body.fetch("shortlist")
  end

  test "malformed input and missing CSRF tokens cannot mutate session state" do
    token = open_search_session
    post "/api/search", params: { message: "STEM" }, as: :json
    assert_response :unprocessable_content
    assert_equal "invalid_csrf_token", response.parsed_body.fetch("error")

    post "/api/search", params: { message: ["STEM"] }, as: :json,
      headers: { "X-CSRF-Token" => token }
    assert_response :unprocessable_content

    post "/api/shortlist", params: { school_id: "unknown" }, as: :json,
      headers: { "X-CSRF-Token" => token }
    assert_response :not_found

    get "/api/session"
    assert_empty response.parsed_body.fetch("history")
    assert_empty response.parsed_body.fetch("shortlist")
  end

  test "the root view and health endpoints respond" do
    get "/"
    assert_response :success
    assert_select "h1", "GreatSchools Guided Search"
    get "/up"
    assert_response :success
    get "/ready"
    assert_response :success
    assert_equal "ready", response.parsed_body.fetch("status")
  end

  private

  def open_search_session
    get "/api/session"
    assert_response :success
    response.parsed_body.fetch("csrf_token")
  end
end
