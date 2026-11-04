require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  class BedrockFlowRetriever < GuidedSearch::OpenSearchRetriever
    def initialize
      school_search = Object.new
      def school_search.search(text:, filters:, geo:, size:)
        unless text.include?("Jacksonville") && filters[:state] == "FL" && filters[:city] == "jacksonville" &&
            [nil, "m"].include?(filters[:level_codes])
          raise "Bedrock preferences did not reach school search"
        end

        schools = [
          { "source" => { "id" => "School fl-12345", "name" => "Test Middle School",
                          "level_codes" => ["m"], "summary_rating" => 9, "latlon" => "30.33, -81.65" } },
          { "source" => { "id" => "School fl-12346", "name" => "Another Middle School",
                          "level_codes" => ["m"], "summary_rating" => 4, "latlon" => "30.34, -81.65" } }
        ]
        unless filters[:level_codes]
          schools << { "source" => { "id" => "School fl-12347", "name" => "Test Elementary School",
            "level_codes" => ["e"], "summary_rating" => 8, "latlon" => "30.32, -81.65" } }
        end
        schools
      end
      super(school_search: school_search)
    end
  end

  test "renders chat, cards and map" do
    get root_path
    assert_response :success
    assert_select "aside", text: /Most programs nearby end at 5:00 pm/
    assert_select "article[data-school-id]", 3
    assert_select "section[aria-label='Map of results'] svg"
    assert_select "article", text: /No rating yet/
  end

  test "the browser can search, follow up, save and remove a school" do
    get root_path
    search = css_select("form[action='/api/search.html']").first
    post search["action"], params: { message: "STEM in Woodstock", authenticity_token: token_for(search) }
    assert_response :see_other
    follow_redirect!
    assert_select "#messages", text: /Which grade and ZIP code/
    assert_select "article[data-school-id='demo-woodstock-stem']", 1
    assert_select "section[aria-label='Map of results'] svg text", 1

    follow_up = css_select("aside form[action='/api/search.html']").first
    assert_equal "guided-search", follow_up["data-turbo-frame"]
    frame_headers = { "Turbo-Frame" => "guided-search", "Accept" => "text/vnd.turbo-stream.html, text/html" }
    post follow_up["action"], params: { message: "Grade 6", authenticity_token: token_for(follow_up) }, headers: frame_headers
    assert_response :see_other
    follow_redirect!(headers: frame_headers)
    assert_select "turbo-frame#guided-search #messages", text: /STEM in Woodstock.*Grade 6/m
    assert_select "turbo-frame#guided-search #results article[data-school-id='demo-woodstock-stem']", 1
    assert_select "turbo-frame#guided-search section[aria-label='Map of results'] svg text", 1

    save = css_select("article form[action='/api/shortlist.html']").first
    post save["action"], params: { school_id: "demo-woodstock-stem", authenticity_token: token_for(save) }
    assert_response :see_other
    follow_redirect!
    assert_select "a[href='/?view=shortlist']", text: /My list \(1\)/

    get root_path(view: "shortlist")
    assert_select "article[data-school-id='demo-woodstock-stem']", 1
    remove = css_select("article form").first
    post remove["action"], params: { _method: "delete", view: "shortlist", authenticity_token: token_for(remove) }
    assert_redirected_to root_path(view: "shortlist")
    follow_redirect!
    assert_select "#results", text: /Your list is empty/
  end

  test "a stored OpenSearch card can be saved and removed using its source ID" do
    get api_search_session_path
    school_id = "School fl-95390"
    SearchSession.sole.update!(
      history: [{ "role" => "assistant", "content" => "Here's a result." }],
      results: [{ "school_id" => school_id, "name" => "Mariner Elementary School", "criteria" => [] }]
    )

    get root_path
    assert_select "article[data-school-id='#{school_id}']", 1
    assert_select "section[aria-label='Map of results'] svg text", 0
    save = css_select("article form").first
    post save["action"], params: { school_id: school_id, authenticity_token: token_for(save) }
    assert_response :see_other

    get root_path(view: "shortlist")
    assert_select "article[data-school-id='#{school_id}']", 1
    remove = css_select("article form").first
    post remove["action"], params: { _method: "delete", view: "shortlist", authenticity_token: token_for(remove) }
    assert_response :see_other
    follow_redirect!
    assert_select "#results", text: /Your list is empty/
  end

  test "Bedrock follow-up results support priority edits, comparison, and profiles" do
    agent_key = "GUIDED_SEARCH_AGENT"
    retriever_key = "GUIDED_SEARCH_RETRIEVER"
    previous_agent, previous_retriever = ENV.values_at(agent_key, retriever_key)
    bedrock_service = Aws::BedrockRuntime::Client.identifier
    previous_bedrock = Aws.config[bedrock_service]
    ENV[agent_key] = "GuidedSearch::BedrockAgent"
    ENV[retriever_key] = "#{self.class.name}::BedrockFlowRetriever"
    Aws.config[bedrock_service] = {
      stub_responses: { converse: lambda do |request|
        context = JSON.parse(request.params[:messages].first[:content].first[:text])
        extracted = { needs: ["Highly rated"], grade_level: "Middle school", filters: { level_codes: "m" } }
        if context.fetch("history").empty?
          extracted.merge!(location: nil, clarifying_question: "What city and state should I search?")
        else
          assert_equal ["Highly rated"], context.dig("preferences", "needs")
          extracted.merge!(location: "Jacksonville, FL", query: "Highly rated middle school in Jacksonville",
            filters: { state: "fl", city: "Jacksonville", level_codes: "m" })
        end
        {
          output: { message: { role: "assistant", content: [{ text: extracted.to_json }] } },
          stop_reason: "end_turn",
          usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 },
          metrics: { latency_ms: 1 }
        }
      end }
    }

    get root_path
    form = css_select("form[action='/api/search.html']").first
    post form["action"], params: { message: "I want a highly rated middle school", authenticity_token: token_for(form) }
    assert_response :see_other
    follow_redirect!
    assert_select "#messages", text: /What city and state should I search/
    assert_select "#results article", 0

    follow_up = css_select("aside form[action='/api/search.html']").first
    post follow_up["action"], params: { message: "Jacksonville, FL", authenticity_token: token_for(follow_up) }
    assert_response :see_other
    follow_redirect!
    assert_select "#messages", text: /I found 2 schools to explore/
    assert_select "#results article", text: /Test Middle School.*Highly rated/m
    assert_select "section[aria-label='Map of results'] svg text", 2

    form = css_select("form[action='/search-options']").find { |node| node.at_css("input[value='toggle']") }
    post search_options_path, params: { change: "toggle", key: "rating", authenticity_token: token_for(form) }
    assert_response :see_other
    follow_redirect!
    assert_select "button[aria-pressed='true']", text: /MUST.*Highly rated/m
    assert_select "#results article", count: 1, text: /Test Middle School/
    assert_select "#results article", count: 0, text: /Another Middle School/

    post search_options_path, params: { change: "toggle", key: "rating", authenticity_token: token_for(form) }
    follow_redirect!
    assert_select "#results article", 2

    add_form = css_select("form[action='/search-options']").find { |node| node.at_css("input[value='add']") }
    post search_options_path, params: { change: "add", need: "Sports programs", authenticity_token: token_for(add_form) }
    follow_redirect!
    assert_select "button[aria-pressed='false']", text: /NICE.*Sports programs/m
    assert_select "#results article", count: 2, text: /Sports programs/

    refresh_form = css_select("form[action='/search-options']").find { |node| node.at_css("input[value='refresh']") }
    post search_options_path, params: { change: "refresh", authenticity_token: token_for(refresh_form) }
    follow_redirect!
    assert_select "button[aria-pressed='false']", text: /NICE.*Sports programs/m

    get compare_schools_path, params: { ids: ["School fl-12345", "School fl-12346"] }
    assert_select "table th a", text: "Test Middle School"
    assert_select "table th a", text: "Another Middle School"
    assert_select "table td", text: "9/10"
    assert_select "table td", text: "4/10"

    get school_profile_path("School fl-12345")
    assert_select "h1", text: "Test Middle School"
    assert_select "#evidence"
    assert_select "a[href='https://www.google.com/maps/search/?api=1&query=30.33%2C-81.65']"

    get root_path
    grade_form = css_select("form[action='/search-options']").find { |node| node.at_css("input[value='grade']") }
    assert_select "button[aria-label='Remove grade filter Middle school']"
    post search_options_path, params: { change: "grade", grade: "", authenticity_token: token_for(grade_form) }
    follow_redirect!
    assert_select "#results article", 3
    assert_select "#results article", text: /Test Elementary School/
    assert_select "button[aria-label^='Remove grade filter']", 0
    assert_select "select#grade option[value='']", text: "Any grade"
    preferences = SearchSession.sole.preferences
    assert_equal "Any grade", preferences["grade_level"]
    assert_nil preferences.dig("filters", "level_codes")
    assert_includes preferences["needs"], "Sports programs"

    grade_form = css_select("form[action='/search-options']").find { |node| node.at_css("input[value='grade']") }
    post search_options_path, params: { change: "grade", grade: "m", authenticity_token: token_for(grade_form) }
    follow_redirect!
    assert_select "#results article", 2
    assert_select "button[aria-label='Remove grade filter 6–8']"
  ensure
    ENV[agent_key], ENV[retriever_key] = previous_agent, previous_retriever
    Aws.config[bedrock_service] = previous_bedrock
  end

  test "an existing card opens the full seeded school profile and can be saved there" do
    get api_search_session_path
    search_session = SearchSession.sole
    search_session.update!(
      history: [{ "role" => "assistant", "content" => "One result." }],
      results: [{ "school_id" => "School fl-98226", "name" => "Bayside Middle School",
        "entity_type" => "public", "grades" => "6–8", "summary_rating" => 4,
        "avg_review_rating" => 3.1, "review_count" => 39, "latlon" => "30.286949, -81.781624", "criteria" => [] }]
    )
    get school_profile_path("School fl-98226")
    assert_response :success
    assert_select ".profile-facts", text: /495 students/
    assert_select "#from-school", text: /3252 Meadow Avenue.*Jacksonville, FL 32203/m
    assert_select "#from-school", text: /Northbrook Unified School District/
    assert_select "#academics", text: /Test scores.*3.*Student progress.*4/m
    assert_select "#school-culture", text: /46.3%.*14/m
    assert_select "#courses-activities", text: /Gifted.*Talented/
    assert_select "#reviews .profile-review", 25
    assert_select ".profile-review details summary", text: "Show full review"
    assert_select "a[href='https://www.example.org/bayside-middle-school/social']", 0
    save = css_select("form[action='/api/shortlist.html']").first
    post save["action"], params: { school_id: "School fl-98226", return_to_profile: "1", authenticity_token: token_for(save) }
    assert_redirected_to school_profile_path("School fl-98226")
    follow_redirect!
    assert_select ".profile-actions button[aria-pressed='true']", text: /Saved/
    get school_profile_path("School fl-98226", view: "shortlist")
    assert_select "#reviews .profile-review", 25
  end

  test "comparison uses distinct visible schools and rejects unknown profiles" do
    get root_path
    ids = css_select("input[form='compare-schools']").map { |input| input["value"] }
    assert_equal 3, ids.size
    get compare_schools_path, params: { ids: [ids.first, ids.first, "unknown"] }
    assert_redirected_to root_path
    get school_profile_path("unknown")
    assert_response :not_found
  end

  private

  def token_for(form)
    form.at_css("input[name=authenticity_token]")["value"]
  end
end
