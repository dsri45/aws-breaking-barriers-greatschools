require "test_helper"

module GuidedSearch
  class EvidenceScorerTest < ActiveSupport::TestCase
    def criterion(key, label = nil, importance = "require")
      { "key" => key, "label" => label || key, "importance" => importance }
    end

    test "null summary_rating is missing, never a low score" do
      row = EvidenceScorer.score(school: { "name" => "No Rating School" },
                                 criteria: [criterion("high_performing")]).first
      assert_equal "missing", row["status"]
      assert_match(/no rating/i, row["evidence"])
      assert_nil row["as_of"]
    end

    test "high rating is confirmed, mid is partial, low is needs_attention" do
      confirmed = EvidenceScorer.score(school: { "summary_rating" => 9 }, criteria: [criterion("high_performing")]).first
      partial   = EvidenceScorer.score(school: { "summary_rating" => 6 }, criteria: [criterion("high_performing")]).first
      low       = EvidenceScorer.score(school: { "summary_rating" => 2 }, criteria: [criterion("high_performing")]).first
      assert_equal "confirmed", confirmed["status"]
      assert_equal "partial", partial["status"]
      assert_equal "needs_attention", low["status"]
    end

    test "tiered object carries its as_of date for staleness" do
      school = { "class_size" => { "tier" => "small", "qualifies" => true,
                                   "source_generated_at" => "2026-07-15T20:06:00Z" } }
      row = EvidenceScorer.score(school: school, criteria: [criterion("class_size", "Class size")]).first
      assert_equal "confirmed", row["status"]
      assert_equal "2026-07-15T20:06:00Z", row["as_of"]
    end

    test "absent osp feature is missing, not needs_attention" do
      row = EvidenceScorer.score(school: {}, criteria: [criterion("busing", "Bus service")]).first
      assert_equal "missing", row["status"]
    end

    test "present transportation is confirmed" do
      school = { "osp" => { "transportation" => ["busses"] } }
      row = EvidenceScorer.score(school: school, criteria: [criterion("busing", "Bus service")]).first
      assert_equal "confirmed", row["status"]
      assert_match(/busses/, row["evidence"])
    end

    test "review evidence summarizes rating and dominant topic" do
      school = {
        "avg_review_rating" => 4.3,
        "sentiment_stats" => {
          "total_reviews" => 6,
          "sentiment_by_topic" => {
            "Teachers / Staff" => { "positive" => 4, "negative" => 1, "total" => 5 },
            "Other" => { "positive" => 1, "negative" => 0, "total" => 1 }
          }
        }
      }
      row = EvidenceScorer.score(school: school, criteria: [criterion("reviews", "Well reviewed")]).first
      assert_equal "confirmed", row["status"]
      assert_match(/Teachers \/ Staff: mostly positive/, row["evidence"])
    end

    test "every status produced is in the allowed set" do
      school = { "summary_rating" => 7, "level_codes" => ["m"], "avg_review_rating" => 2.0,
                 "sentiment_stats" => { "total_reviews" => 3 } }
      rows = EvidenceScorer.score(
        school: school,
        criteria: [criterion("high_performing"), criterion("level"), criterion("reviews"), criterion("class_size")]
      )
      rows.each { |r| assert_includes EvidenceScorer::STATUSES, r["status"] }
    end
  end
end
