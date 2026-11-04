require "test_helper"

class ChatSessionsTest < ActionDispatch::IntegrationTest
  test "new chat clears the workspace and history resumes its complete saved state" do
    get root_path
    assert_select ".search-grade-label", text: "New chat"
    form = css_select(".guide-start-form").first
    post form["action"], params: { message: "STEM in Woodstock", authenticity_token: token_for(form) }
    follow_redirect!
    original = SearchSession.sole
    school_id = original.results.first.fetch("id")
    save = css_select("article form[action^='/api/shortlist.html']").first
    post save["action"], params: { school_id: school_id, authenticity_token: token_for(save) }
    follow_redirect!
    state = original.reload.attributes.slice("history", "preferences", "results", "follow_up_questions")

    form = css_select("nav[aria-label='Chat sessions'] form").first
    assert_difference("SearchSession.count", 1) do
      post form["action"], params: { authenticity_token: token_for(form) }
    end
    fresh = SearchSession.order(:id).last
    assert_redirected_to chat_path(fresh.id)
    follow_redirect!
    assert_select ".guide-welcome", 1
    assert_select "#messages", text: /Let's get to know your learner/
    assert_select "#messages", count: 0, text: /STEM in Woodstock/
    assert_select "a", text: "My list (0)"
    assert_empty fresh.preferences
    assert_empty fresh.results
    assert_empty fresh.follow_up_questions
    assert_empty fresh.shortlist_entries
    assert_equal state, original.reload.attributes.slice(*state.keys)
    assert_equal [school_id], original.shortlist_entries.pluck(:school_id)
    assert_select ".guide-start-form[action='/api/search.html?chat_id=#{fresh.id}']"

    get chats_path
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "li h2", text: "STEM in Woodstock"
    assert_select "li", 1
    assert_select "a[href='/chats/#{original.id}']", text: "Resume"
    get chat_path(original.id)
    assert_response :success
    assert_select "#messages", text: /STEM in Woodstock/
    assert_select "a", text: "My list (1)"
    assert_select "aside form[action='/api/search.html?chat_id=#{original.id}']"
    assert_select "[data-school-comparison-chat-id-value='#{original.id}']"
    assert_equal state, original.reload.attributes.slice(*state.keys)
    get api_search_session_path
    assert_equal state["history"], response.parsed_body["history"]
  end

  test "older tab requests remain scoped to their chat after another chat becomes active" do
    get api_search_session_path
    token = response.parsed_body.fetch("csrf_token")
    original = SearchSession.sole
    post api_search_path, params: { message: "STEM" }, as: :json, headers: { "X-CSRF-Token" => token }
    post chats_path, params: { authenticity_token: token }
    fresh = SearchSession.order(:id).last
    get chat_path(fresh.id)

    post api_search_path(chat_id: original.id), params: { message: "Grade 6" }, as: :json,
      headers: { "X-CSRF-Token" => token }
    assert_response :success
    assert_equal ["STEM", "Grade 6"], original.reload.history.select { |m| m["role"] == "user" }.pluck("content")
    assert_empty fresh.reload.history
    get chat_path(fresh.id)
    assert_select ".guide-welcome", 1
  end

  test "another browser cannot list, open, or change a conversation" do
    get api_search_session_path
    token = response.parsed_body.fetch("csrf_token")
    post api_search_path, params: { message: "STEM" }, as: :json, headers: { "X-CSRF-Token" => token }
    original = SearchSession.sole
    original_history = original.history
    other = open_session
    other.get chats_path
    assert_equal 200, other.response.status
    assert_not_includes other.response.body, "Resume STEM"
    other.get chat_path(original.id)
    assert_equal 404, other.response.status
    other.get api_search_session_path
    other_token = other.response.parsed_body.fetch("csrf_token")
    other.post api_search_path(chat_id: original.id), params: { message: "Changed" }, as: :json,
      headers: { "X-CSRF-Token" => other_token }
    assert_equal 404, other.response.status
    other.post api_shortlist_index_path(chat_id: original.id), params: { school_id: original.results.first.fetch("id") },
      as: :json, headers: { "X-CSRF-Token" => other_token }
    assert_equal 404, other.response.status
    assert_equal original_history, original.reload.history
    assert_empty original.shortlist_entries
  end

  test "the existing encrypted session can claim its legacy chat but not another legacy chat" do
    get api_search_session_path
    original = SearchSession.sole
    original.update!(browser_token_digest: nil, history: [{ "role" => "user", "content" => "Legacy chat" }])
    orphan = SearchSession.create!(history: [{ "role" => "user", "content" => "Unrelated legacy chat" }])
    cookies.delete(:guided_search_browser)
    get root_path
    assert_response :success
    assert_match(/\A[0-9a-f]{64}\z/, original.reload.browser_token_digest)
    get chats_path
    assert_select "li h2", text: "Legacy chat"
    assert_select "li h2", text: "Unrelated legacy chat", count: 0
    get chat_path(orphan.id)
    assert_response :not_found
    assert_nil orphan.reload.browser_token_digest
  end

  test "the browser can still resume history after the active Rails session ends" do
    get api_search_session_path
    original = SearchSession.sole
    original.update!(history: [{ "role" => "user", "content" => "My remembered search" }])
    returning_browser = open_session
    returning_browser.cookies[:guided_search_browser] = cookies[:guided_search_browser]
    returning_browser.get chats_path
    assert_equal 200, returning_browser.response.status
    assert_includes returning_browser.response.body, "My remembered search"
    returning_browser.get chat_path(original.id)
    assert_equal 200, returning_browser.response.status
    returning_browser.get api_search_session_path
    assert_equal original.history, returning_browser.response.parsed_body["history"]
  end

  test "history is paginated and empty chats stay out of the list" do
    get api_search_session_path
    owner = SearchSession.sole.browser_token_digest
    21.times do |index|
      SearchSession.create!(browser_token_digest: owner,
        history: [{ "role" => "user", "content" => "School search #{index}" }])
    end
    get chats_path
    assert_select "li", 20
    assert_select "nav[aria-label='Chat history pages']", text: /Page 1 of 2/
    get chats_path(page: 2)
    assert_select "li", 1
    assert_select "li h2", text: "School search 0"
  end

  test "new chat requires CSRF and retrying on a blank chat does not create more chats" do
    get root_path
    form = css_select("nav[aria-label='Chat sessions'] form").first
    assert_no_difference("SearchSession.count") do
      post chats_path
      assert_response :unprocessable_content
    end
    assert_no_difference("SearchSession.count") do
      post form["action"], params: { authenticity_token: token_for(form) }
      assert_redirected_to chat_path(SearchSession.sole.id)
    end
    get "/chats/not-an-id"
    assert_response :not_found
    get chats_path(format: :json)
    assert_response :not_acceptable
  end

  private

  def token_for(form)
    form.at_css("input[name=authenticity_token]")["value"]
  end
end
