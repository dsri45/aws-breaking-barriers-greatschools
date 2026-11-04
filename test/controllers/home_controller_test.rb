require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  class ReadingClubRetriever < GuidedSearch::OpenSearchRetriever
    def initialize
      search = Object.new
      def search.search(text:, filters:, geo:, size:)
        unless filters.slice(:state, :level_codes, :reading_club) == { state: "FL", level_codes: "e", reading_club: true }
          raise "Reading-club and grade requirements did not reach search"
        end

        JSON.parse(Rails.root.join("db/seeds/school_data.json").read)
          .select { |school| school["state"] == filters[:state] && school["level_codes"].include?(filters[:level_codes]) }
          .map { |school| { "source" => school } }
      end
      super(school_search: search)
    end
  end

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
    assert_select ".guide-welcome", text: /Let's get to know your learner/
    assert_select ".guide-start-form textarea#follow_up_message", 1
    assert_select ".guide-starters button", 3
    assert_select "article[data-school-id]", 0
    assert_select "section[aria-label='Map of results']", text: /Matching school locations will appear here/
    assert_select ".search-priority", 0
    assert_select "#results", text: /Start with your location/
    assert_not_includes response.body, "Woodstock"
    assert_not_includes response.body, "Example priorities"
  end

  test "the requested reading club stays primary from the prompt through the displayed recommendation" do
    previous_agent, previous_retriever = ENV.values_at("GUIDED_SEARCH_AGENT", "GUIDED_SEARCH_RETRIEVER")
    service = Aws::BedrockRuntime::Client.identifier
    previous_bedrock = Aws.config[service]
    ENV["GUIDED_SEARCH_AGENT"] = "GuidedSearch::BedrockAgent"
    ENV["GUIDED_SEARCH_RETRIEVER"] = "#{self.class.name}::ReadingClubRetriever"
    Aws.config[service] = { stub_responses: { converse: {
      output: { message: { role: "assistant", content: [{ text: {
        needs: ["Arts programs"], location: "FL", grade_level: "e", query: "arts schools in FL",
        filters: { state: "FL", level_codes: "e" }
      }.to_json }] } }, stop_reason: "end_turn",
      usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 }, metrics: { latency_ms: 1 }
    } } }
    get root_path
    form = css_select(".guide-start-form").first
    post form["action"], params: { message: "give me an elementary school with a reading club in FL",
      authenticity_token: token_for(form) }
    assert_response :see_other
    follow_redirect!
    assert_select "#results article", 1
    assert_select "article[data-school-id='School fl-96528']", text: /Bluewater Charter School.*Reading club.*book club/m
    assert_select "[data-guide-latest-response]", text: /priorities of Elementary school and Reading club.*match for reading club.*book club/m
    assert_select ".search-priority", text: /Arts programs/, count: 0
    assert_select ".search-grade-label", text: "Elementary school"
    assert_equal ["Reading club"], SearchSession.sole.preferences["needs"]
  ensure
    ENV["GUIDED_SEARCH_AGENT"], ENV["GUIDED_SEARCH_RETRIEVER"] = previous_agent, previous_retriever
    Aws.config[service] = previous_bedrock
  end

  test "the browser can search, follow up, save and remove a school" do
    get root_path
    search = css_select("form[action^='/api/search.html']").first
    post search["action"], params: { message: "STEM in Woodstock", authenticity_token: token_for(search) }
    assert_response :see_other
    follow_redirect!
    assert_select "#messages", text: /Which grade and ZIP code/
    assert_select "article[data-school-id='demo-woodstock-stem']", 1
    assert_select "section[aria-label='Map of results'] svg text", 1

    follow_up = css_select("aside form[action^='/api/search.html']").first
    assert_equal "guided-search", follow_up["data-turbo-frame"]
    frame_headers = { "Turbo-Frame" => "guided-search", "Accept" => "text/vnd.turbo-stream.html, text/html" }
    post follow_up["action"], params: { message: "Grade 6", authenticity_token: token_for(follow_up) }, headers: frame_headers
    assert_response :see_other
    follow_redirect!(headers: frame_headers)
    assert_select "turbo-frame#guided-search #messages", text: /STEM in Woodstock.*Grade 6/m
    assert_select "turbo-frame#guided-search #results article[data-school-id='demo-woodstock-stem']", 1
    assert_select "turbo-frame#guided-search section[aria-label='Map of results'] svg text", 1

    save = css_select("article form[action^='/api/shortlist.html']").first
    post save["action"], params: { school_id: "demo-woodstock-stem", authenticity_token: token_for(save) }
    assert_response :see_other
    follow_redirect!
    assert_select "a", text: /My list \(1\)/

    get root_path(view: "shortlist")
    assert_select "article[data-school-id='demo-woodstock-stem']", 1
    remove = css_select("article form").first
    post remove["action"], params: { _method: "delete", view: "shortlist", authenticity_token: token_for(remove) }
    assert_redirected_to chat_path(SearchSession.sole.id, view: "shortlist")
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

  test "unverified stored program results disappear from cards, map, and profiles" do
    get api_search_session_path
    SearchSession.sole.update!(
      history: [{ "role" => "assistant", "content" => "An older search." }],
      preferences: { "criteria" => [{ "key" => "sports_programs", "label" => "Sports programs", "importance" => "prefer" }] },
      results: [
        { "school_id" => "unverified", "name" => "Unverified school", "latlon" => "29,-82",
          "criteria" => [{ "key" => "sports_programs", "status" => "missing", "evidence" => "No sports data" }] },
        { "school_id" => "verified", "name" => "Verified school", "latlon" => "29,-82",
          "criteria" => [{ "key" => "sports_programs", "status" => "confirmed", "evidence" => "Sports: soccer" }] }
      ]
    )
    get root_path
    assert_select "#results article", 1
    assert_select "article[data-school-id='verified']"
    assert_select "section[aria-label='Map of results'] svg text", 1
    assert_select "#results", count: 0, text: /Unverified school/
    get school_profile_path("unverified")
    assert_response :not_found
    get api_search_session_path
    assert_equal ["verified"], response.parsed_body["results"].pluck("school_id")
    token = response.parsed_body.fetch("csrf_token")
    post api_shortlist_index_path, params: { school_id: "unverified" }, as: :json, headers: { "X-CSRF-Token" => token }
    assert_response :not_found
    assert_empty SearchSession.sole.shortlist_entries
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
    form = css_select("form[action^='/api/search.html']").first
    post form["action"], params: { message: "I want a highly rated middle school", authenticity_token: token_for(form) }
    assert_response :see_other
    follow_redirect!
    assert_select "#messages", text: /What city and state should I search/
    assert_select "#results article", 0

    follow_up = css_select("aside form[action^='/api/search.html']").first
    post follow_up["action"], params: { message: "Jacksonville, FL", authenticity_token: token_for(follow_up) }
    assert_response :see_other
    follow_redirect!
    assert_select "#messages", text: /I found one school to explore/
    assert_select "#results article", text: /Test Middle School.*Highly rated/m
    assert_select ".guide-response", text: /Test Middle School.*GreatSchools summary rating 9\/10.*On a visit/m
    assert_select ".guide-next button", text: "Why these schools?"
    assert_select "section[aria-label='Map of results'] svg text", 1

    form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='toggle']") }
    assert_select "button[aria-pressed='true']", text: /Highly rated/
    post search_options_path, params: { change: "toggle", key: "rating", authenticity_token: token_for(form) }
    follow_redirect!
    assert_select "button[aria-pressed='false']", text: /Highly rated/
    assert_select "#results article", 2

    add_form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='add']") }
    post search_options_path, params: { change: "add", need: "Sports programs", authenticity_token: token_for(add_form) }
    follow_redirect!
    assert_select "button[aria-pressed='true']", text: /Sports programs/
    assert_select "#results article", 0

    post search_options_path, params: { change: "toggle", key: "sports_programs", authenticity_token: token_for(add_form) }
    follow_redirect!
    assert_select "button[aria-pressed='false']", text: /Sports programs/
    assert_select "#results article", 0

    refresh_form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='refresh']") }
    post search_options_path, params: { change: "refresh", authenticity_token: token_for(refresh_form) }
    follow_redirect!
    assert_select "button[aria-pressed='false']", text: /Sports programs/

    remove_form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='remove']") }
    post remove_form["action"], params: { change: "remove", key: "sports_programs", authenticity_token: token_for(remove_form) }
    follow_redirect!
    assert_select "#results article", 2
    assert_not_includes SearchSession.sole.preferences["needs"], "Sports programs"

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
    grade_form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='grade']") }
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
    assert_not_includes preferences["needs"], "Sports programs"

    grade_form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='grade']") }
    post search_options_path, params: { change: "grade", grade: "m", authenticity_token: token_for(grade_form) }
    follow_redirect!
    assert_select "#results article", 2
    assert_select "button[aria-label='Remove grade filter 6–8']"

    add_form = css_select("form[action^='/search-options']").find { |node| node.at_css("input[value='add']") }
    post search_options_path, params: { change: "add", need: "IB offered", authenticity_token: token_for(add_form) }
    follow_redirect!
    assert_select "#results article", 0
    assert_select "button[aria-pressed='true']", text: /IB offered/
    assert_equal "m", SearchSession.sole.preferences.dig("filters", "level_codes")
    assert_equal "require", SearchSession.sole.preferences.dig("priority_overrides", "ib")
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
    save = css_select("form[action^='/api/shortlist.html']").first
    post save["action"], params: { school_id: "School fl-98226", return_to_profile: "1", authenticity_token: token_for(save) }
    assert_redirected_to school_profile_path("School fl-98226", chat_id: SearchSession.sole.id)
    follow_redirect!
    assert_select ".profile-actions button[aria-pressed='true']", text: /Saved/
    get school_profile_path("School fl-98226", view: "shortlist")
    assert_select "#reviews .profile-review", 25
  end

  test "comparison uses distinct visible schools and rejects unknown profiles" do
    get api_search_session_path
    data = JSON.parse(Rails.root.join("db/sample/results.json").read)
    SearchSession.sole.update!(results: data["results"], history: [{ "role" => "assistant", "content" => "Three schools." }])
    get root_path
    ids = css_select("input[form='compare-schools']").map { |input| input["value"] }
    assert_equal 3, ids.size
    get compare_schools_path, params: { ids: [ids.first, ids.first, "unknown"] }
    assert_redirected_to root_path(chat_id: SearchSession.sole.id)
    get school_profile_path("unknown")
    assert_response :not_found
  end

  test "school profiles expose support, admissions, school details and all published offerings" do
    get api_search_session_path
    school = SchoolProfile.seed_schools.fetch("School fl-96528")
    SearchSession.sole.update!(history: [{ "role" => "assistant", "content" => "One school." }], results: [{
      "school_id" => school["id"], "name" => school["name"], "grades" => "PK, K–12", "entity_type" => "charter",
      "summary_rating" => school["summary_rating"], "criteria" => [],
      "profile" => { "osp" => { "school_phone" => ["850-555-0100"] } }
    }])
    get school_profile_path(school["id"])
    assert_response :success
    assert_select ".profile-section-nav a[href='#student-support']", text: "Student support"
    assert_select "#student-support", text: /Mental health supports.*Mental health specialists.*Family engagement.*Parent-teacher conferences/m
    assert_select "#from-school", text: /850-555-0100.*See all school info.*850-555-0116.*Start time.*8:00 AM.*Schedule.*Traditional/m
    assert_select "#enrollment time[datetime='2050-01-01']", text: "January 1, 2050"
    assert_select "#enrollment", text: /Requirements.*Application/m
    assert_select "#courses-activities", text: /Book \/ reading club.*College preparation.*College guidance.*Career exploration/m
    assert_select "#courses-activities details summary", text: /Show all 11 academic clubs offerings/
    assert_select "#reviews details summary", text: "Review topics & sentiment"
    assert_select "#reviews table th", text: "Teachers / Staff"
    assert_select "#academics", text: /10-point scale/
    assert_select "a[href^='javascript:']", 0
  end

  test "a sparse school profile shows missing data clearly without invented percentages or stars" do
    get api_search_session_path
    SearchSession.sole.update!(history: [{ "role" => "assistant", "content" => "One school." }], results: [{
      "school_id" => "no-data", "name" => "Sparse School", "criteria" => [],
      "profile" => { "osp" => { "application_deadline_date" => ["2022-02-28"] } }
    }])
    get school_profile_path("no-data")
    assert_response :success
    assert_select "#student-support", text: /English learning support information is not provided.*No published mental health supports information/m
    assert_select "#enrollment", text: /Past deadline.*Not provided/m
    assert_select "#academics", text: /Academic ratings are not provided/
    assert_select "#academics .profile-details", 0
    assert_select "#reviews .profile-review-topics", 0
  end

  test "inline school actions explain evidence without changing search preferences" do
    get api_search_session_path
    search_session = SearchSession.sole
    preferences = { "location" => "Jacksonville, FL", "grade_level" => "Middle school", "needs" => ["Highly rated"] }
    school = {
      "school_id" => "School fl-guide", "name" => "Guide Middle School", "grades" => "6–8", "summary_rating" => 9,
      "criteria" => [
        { "key" => "rating", "label" => "Highly rated", "status" => "confirmed", "evidence" => "GreatSchools summary rating 9/10" },
        { "key" => "sports_programs", "label" => "Sports programs", "status" => "missing", "evidence" => "No sports program data published" }
      ]
    }
    search_session.update!(preferences: preferences, results: [school], history: [{ "role" => "assistant", "content" => "A school to explore." }])
    get root_path
    form = css_select("article form[action^='/api/search.html']").find { |node| node.at_css("input[value='explain_school']") }
    post form["action"], params: { message: "Why this school?", intent: "explain_school",
      school_id: "School fl-guide", authenticity_token: token_for(form) }
    follow_redirect!
    assert_select ".guide-response", text: /Why it made your shortlist.*rating 9\/10.*No sports program data published/m
    assert_equal preferences, search_session.reload.preferences
    assert_equal [school], search_session.results

    form = css_select("article form[action^='/api/search.html']").find { |node| node.at_css("input[value='visit_questions']") }
    post form["action"], params: { message: "Plan a visit", intent: "visit_questions",
      school_id: "School fl-guide", authenticity_token: token_for(form) }
    follow_redirect!
    assert_select ".guide-response", text: /Which sports are offered for this grade/

    history = search_session.reload.history
    post api_search_path(format: :html), params: { message: "Explain an unrelated school", intent: "explain_school",
      school_id: "not-owned", authenticity_token: token_for(form) }
    assert_response :see_other
    assert_equal history, search_session.reload.history

    search_session.shortlist_entries.create!(school_id: "School fl-guide", school: school)
    current_results = [{ "school_id" => "School current", "name" => "Current search school", "criteria" => [] }]
    search_session.update!(results: current_results)
    get root_path(view: "shortlist")
    form = css_select(".guide-next form").find { |node| node.at_css("input[value='explain_results']") }
    post form["action"], params: { message: "Explain my saved schools", intent: "explain_results", view: "shortlist", authenticity_token: token_for(form) }
    assert_redirected_to chat_path(SearchSession.sole.id, view: "shortlist")
    follow_redirect!
    assert_select "[data-guide-latest-response]", text: /Guide Middle School.*rating 9\/10/m
    assert_select "[data-guide-latest-response]", count: 0, text: /Current search school/
    assert_equal current_results, search_session.reload.results
  end

  private

  def token_for(form)
    form.at_css("input[name=authenticity_token]")["value"]
  end
end
