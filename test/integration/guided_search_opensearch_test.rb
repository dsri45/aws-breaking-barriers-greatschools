require "test_helper"

# Live OpenSearch integration for the search & data layer. Skipped unless
# OPENSEARCH_URL points at a reachable node (see test/support).
class GuidedSearchOpenSearchTest < ActiveSupport::TestCase
  include OpenSearchIntegration::Helpers

  setup { skip_unless_opensearch }

  def search(index, id)
    GuidedSearch::OpenSearch.new
      .request("POST", "/#{index}/_search", body: { query: { term: { id: id } }, size: 1 })
      .dig("hits", "hits", 0, "_source")
  end

  test "indexes exist with the expected document counts" do
    indexer = GuidedSearch::Indexer.new
    assert indexer.exists?("schools")
    assert indexer.exists?("programs")
    assert_equal 25, indexer.count("schools")
    assert_equal 25, indexer.count("programs")
  end

  test "schools load with geo_point and embedding, preserving absent fields" do
    mariner = search("schools", "School fl-95390")
    assert_equal "Mariner Elementary School", mariner["name"]
    assert_equal({ "lat" => 30.265089, "lon" => -81.751519 }, mariner["location"])
    assert_equal 1024, mariner["embedding"].length

    northwind = search("schools", "School fl-98322")
    refute northwind.key?("summary_rating"), "absent rating must stay absent"
    refute northwind.key?("osp")
    refute northwind.key?("reviews_full")
  end

  test "programs load with nested instances and a visible past status" do
    program = search("programs", "Program ny-937194")
    assert program["instances"].any? { |i| i["status"] == "past" }
    assert program["location"].key?("lat")
  end

  test "BM25 rating filter excludes out-of-range and absent-rating schools" do
    hits = GuidedSearch::SchoolSearch.new.bm25({ filters: { min_summary_rating: 8 } }, size: 25)
    ratings = hits.map { |h| h["source"]["summary_rating"] }
    assert ratings.all? { |r| r && r >= 8 }, "only 8..10 rated schools should match"
    assert hits.size.positive?
  end

  test "geo-distance search returns only nearby schools" do
    hits = GuidedSearch::SchoolSearch.new.bm25(
      { geo: { lat: 30.33, lon: -81.65, radius_km: 20 } }, size: 25
    )
    assert hits.size.positive?
    hits.each { |h| assert h["source"]["city_untokenized"].present? }
  end

  test "hybrid search blends legs and returns leg scores" do
    hits = GuidedSearch::SchoolSearch.new.search(text: "arts and music", size: 5)
    assert hits.size.positive?
    assert hits.first.key?("bm25")
    assert hits.first.key?("knn")
  end

  test "program age-range filter serves a 9-year-old" do
    hits = GuidedSearch::ProgramSearch.new.bm25({ filters: { age: 9 } }, size: 25)
    assert hits.size.positive?
    hits.each do |h|
      assert h["source"]["age_min_search"] <= 9
      assert h["source"]["age_max_search"] >= 9
    end
  end

  test "retriever returns the card contract shape with Ruby-scored evidence" do
    cards = GuidedSearch::OpenSearchRetriever.new.call(preferences: {
      "query" => "high performing public school",
      "criteria" => [
        { "key" => "high_performing", "label" => "High performing", "importance" => "require" },
        { "key" => "busing", "label" => "Bus service", "importance" => "prefer" }
      ],
      "filters" => { "entity_type" => "public" },
      "geo" => { "lat" => 30.33, "lon" => -81.65, "radius_km" => 40 },
      "size" => 3
    })

    assert cards.size.positive?
    card = cards.first
    %w[school_id name entity_type grades distance_mi summary_rating
       avg_review_rating review_count review_topic latlon saved criteria].each do |key|
      assert card.key?(key), "card missing #{key}"
    end
    card["criteria"].each do |row|
      assert_includes GuidedSearch::EvidenceScorer::STATUSES, row["status"]
    end
    # summary_rating is an integer or nil, never a fabricated low score.
    assert(card["summary_rating"].nil? || card["summary_rating"].is_a?(Integer))
  end
end
