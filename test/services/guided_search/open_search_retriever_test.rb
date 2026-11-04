require "test_helper"

module GuidedSearch
  class OpenSearchRetrieverTest < ActiveSupport::TestCase
    class SchoolSearchStub
      attr_reader :query

      def initialize(sources)
        @sources = sources
      end

      def search(**query)
        @query = query
        @sources.map { |source| { "source" => source } }
      end
    end

    test "MUST IB excludes missing and false program data and preserves the grade filter" do
      search = SchoolSearchStub.new([
        { "id" => "missing", "name" => "Elementary school", "level_codes" => ["e"] },
        { "id" => "offered", "name" => "IB middle school", "level_codes" => ["m"], "ib_offered" => true },
        { "id" => "not-offered", "name" => "Middle school", "level_codes" => ["m"], "ib_offered" => false },
        { "id" => "program-list", "name" => "IB programme", "level_codes" => ["m"], "ib_programs" => ["Middle Years Programme"] }
      ])
      results = OpenSearchRetriever.new(school_search: search).call(preferences: {
        "filters" => { "level_codes" => "m", "state" => "FL" },
        "criteria" => [{ "key" => "ib", "label" => "IB offered", "importance" => "require" }]
      })
      assert_equal %w[offered program-list], results.pluck("school_id")
      assert_equal({ level_codes: "m", state: "FL", ib_offered: true }, search.query[:filters])
      assert_equal ["confirmed"], results.flat_map { |result| result["criteria"].pluck("status") }.uniq
    end

    test "sports requests exclude unverified schools even when NICE" do
      search = SchoolSearchStub.new([
        { "id" => "unknown", "name" => "Unknown sports" },
        { "id" => "sports", "name" => "Published sports", "osp" => { "boys_sports" => ["soccer"] } },
        { "id" => "also-unknown", "name" => "Also unknown" }
      ])
      results = OpenSearchRetriever.new(school_search: search).call(preferences: {
        "criteria" => [{ "key" => "sports_programs", "label" => "Sports programs", "importance" => "prefer" }]
      })
      assert_equal %w[sports], results.pluck("school_id")
      assert_match(/soccer/, results.first["criteria"].first["evidence"])
    end

    test "an older IB criterion key also requires published evidence" do
      search = SchoolSearchStub.new([{ "id" => "unknown", "name" => "No IB information" }])
      results = OpenSearchRetriever.new(school_search: search).call(preferences: {
        "criteria" => [{ "key" => "ib_offered", "label" => "IB offered", "importance" => "require" }]
      })
      assert_empty results
      assert_equal true, search.query.dig(:filters, :ib_offered)
    end

    test "sports and after-school clubs must both be documented, with no substitution from reviews or regular clubs" do
      sports = { "boys_sports" => ["soccer"] }
      search = SchoolSearchStub.new([
        { "id" => "review-only", "reviews_text" => "There are lots of sports and clubs" },
        { "id" => "sports-only", "osp" => sports },
        { "id" => "timing-unknown", "osp" => sports.merge("student_clubs" => ["chess"]) },
        { "id" => "pe-only", "osp" => { "boys_sports" => ["pe_classes"] }, "after_school_clubs" => ["chess"] },
        { "id" => "verified", "osp" => sports, "after_school_clubs" => ["chess"] }
      ])
      results = OpenSearchRetriever.new(school_search: search).call(preferences: {
        "criteria" => [
          { "key" => "sports_programs", "label" => "Sports programs", "importance" => "prefer" },
          { "key" => "after_school_clubs", "label" => "After-school clubs", "importance" => "prefer" }
        ]
      })
      assert_equal ["verified"], results.pluck("school_id")
      assert_equal %w[confirmed confirmed], results.first["criteria"].pluck("status")
      assert_match(/soccer/, results.first["criteria"].first["evidence"])
      assert_match(/chess/, results.first["criteria"].last["evidence"])
    end

    test "school search sends both IB availability and grade restrictions to OpenSearch" do
      client = Object.new
      def client.request(method, path, body:)
        @body = body
        { "hits" => { "hits" => [] } }
      end
      def client.body = @body

      SchoolSearch.new(client: client, embeddings: Object.new).bm25({ filters: { ib_offered: true, level_codes: "m" } })
      filters = client.body.dig(:query, :bool, :filter)
      assert_includes filters, { term: { level_codes: "m" } }
      assert_includes filters, { bool: { should: [
        { term: { ib_offered: true } }, { exists: { field: "ib_programs" } }
      ], minimum_should_match: 1 } }
    end

    test "a reading request selects a published book club and excludes arts-only schools" do
      sources = JSON.parse(Rails.root.join("db/seeds/school_data.json").read)
        .select { |school| school["state"] == "FL" && school["level_codes"].include?("e") }
      search = SchoolSearchStub.new(sources)
      results = OpenSearchRetriever.new(school_search: search).call(preferences: {
        "query" => "elementary school with a reading club in FL",
        "criteria" => [{ "key" => "reading_club", "label" => "Reading club", "importance" => "prefer" }],
        "filters" => { "state" => "FL", "level_codes" => "e" }
      })
      assert_equal ["School fl-96528"], results.pluck("school_id")
      assert_equal({ state: "FL", level_codes: "e", reading_club: true }, search.query[:filters])
      assert_match(/book club/, results.first["criteria"].first["evidence"])
      assert_equal "confirmed", results.first["criteria"].first["status"]
    end

    test "reading scores, generic reviews, and art clubs do not confirm a reading club" do
      search = SchoolSearchStub.new([
        { "id" => "academic", "test_scores_rating" => 10, "reviews_text" => "Children love reading" },
        { "id" => "arts", "osp" => { "student_clubs" => ["art_club"], "arts_visual" => ["painting"] } },
        { "id" => "missing", "osp" => { "student_clubs" => [nil, "", "not a book club"] } }
      ])
      results = OpenSearchRetriever.new(school_search: search).call(preferences: {
        "criteria" => [{ "key" => "reading_club", "label" => "Reading club", "importance" => "require" }]
      })
      assert_empty results
    end

    test "reading club retrieval uses structured club filters even without mentions in school reviews" do
      client = Object.new
      def client.request(method, path, body:)
        @body = body
        { "hits" => { "hits" => [] } }
      end
      def client.body = @body

      SchoolSearch.new(client: client, embeddings: Object.new).bm25(
        { text: "reading club", filters: { reading_club: true, state: "FL", level_codes: "e" } })
      query = client.body.dig(:query, :bool)
      assert_equal [{ match_all: {} }], query[:must]
      assert_includes query[:filter], { term: { state: "FL" } }
      assert_includes query[:filter], { term: { level_codes: "e" } }
      club_filter = query[:filter].find { |filter| filter.key?(:bool) }
      assert_equal 1, club_filter.dig(:bool, :minimum_should_match)
      assert_includes club_filter.dig(:bool, :should).first.dig(:terms, "osp.student_clubs"), "book_club"
      assert query[:should].any? { |clause| clause.key?(:multi_match) }
    end
  end
end
