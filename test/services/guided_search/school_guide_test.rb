require "test_helper"

module GuidedSearch
  class SchoolGuideTest < ActiveSupport::TestCase
    test "a confirmed reading club leads the explanation even when arts evidence appears first" do
      guide = SchoolGuide.new({ "name" => "Reading and arts school", "criteria" => [
        { "key" => "arts", "label" => "Arts programs", "status" => "confirmed", "evidence" => "Visual arts: painting" },
        { "key" => "reading_club", "label" => "Reading club", "status" => "confirmed", "evidence" => "Published reading/book clubs: book club" }
      ] })
      assert_match(/match for reading club/, guide.short_reason)
      assert_operator guide.explanation.index("Reading club"), :<, guide.explanation.index("Arts programs")
      assert_match(/Which books does the reading club/, guide.visit_reply)
    end

    test "recommendations explain a confirmed match and flag missing evidence" do
      school = {
        "name" => "Example Middle School", "summary_rating" => 9,
        "criteria" => [
          { "key" => "rating", "label" => "Highly rated", "status" => "confirmed", "evidence" => "GreatSchools summary rating 9/10" },
          { "key" => "sports_programs", "label" => "Sports programs", "status" => "missing", "evidence" => "No sports program data published" }
        ]
      }
      reply = SchoolGuide.recommendations(preferences: { "location" => "Florida" }, results: [school])
      assert_includes reply, "I found one school to explore"
      assert_includes reply, "Example Middle School"
      assert_includes reply, "GreatSchools summary rating 9/10"
      assert_includes reply, "No sports program data published"
      assert_includes reply, "Which sports are offered for this grade"
      assert_not_includes reply, "sports are not offered"
    end

    test "missing evidence is never promoted into a recommendation strength" do
      guide = SchoolGuide.new({
        "name" => "An unrated school",
        "criteria" => [{ "key" => "ib", "label" => "IB offered", "status" => "missing", "evidence" => "No IB program data published" }]
      })
      assert_match(/does not yet confirm/, guide.short_reason)
      assert_includes guide.explanation, "No IB program data published"
      assert_not_includes guide.explanation, "IB not offered"
      assert_match(/Which IB programme/, guide.visit_reply)
    end

    test "empty results explain required evidence and offer a refinement" do
      reply = SchoolGuide.recommendations(preferences: {
        "location" => "Florida",
        "criteria" => [{ "key" => "ib", "label" => "IB offered", "importance" => "require" }]
      }, results: [])
      assert_includes reply, "published evidence for IB offered"
      assert_includes reply, "published evidence"
      assert_includes reply, "change the requested priorities"
    end
  end
end
