require "test_helper"

class SchoolProfileTest < ActiveSupport::TestCase
  Card = Struct.new(:school_id, :profile, :summary_rating, keyword_init: true)

  test "a partial card retains the complete seeded school record" do
    card = Card.new(school_id: "School fl-96528", profile: { "osp" => { "school_phone" => ["850-555-0100"] } })
    profile = SchoolProfile.for(card)
    assert_equal "850-555-0100", profile.phone
    assert_includes profile.programs["Academic clubs"], "Book / reading club"
    assert_equal Date.new(2050, 1, 1), profile.application_deadline_date
    assert_equal ["Application"], profile.application_requirements
    assert profile.support_programs["Family engagement"].any?
  end

  test "opening a profile refreshes the complete source without filling its missing fields with stale data" do
    card = Card.new(school_id: "School fl-96528", profile: { "osp" => { "school_phone" => ["stale"] } })
    client = Object.new
    def client.request(method, path)
      raise "wrong document" unless method == "GET" && path.end_with?("School%20fl-96528")
      { "_source" => { "name" => "Current school record", "osp" => { "school_phone" => ["850-555-0199"] } } }
    end
    profile = SchoolProfile.for(card, refresh: true, client: client)
    assert_equal "850-555-0199", profile.phone
    assert_nil profile.enrollment
    assert_empty profile.programs["Academic clubs"]
    assert_nil profile.application_deadline
  end

  test "a failed profile refresh retains available card and seed data" do
    client = Object.new
    def client.request(*) = raise GuidedSearch::UpstreamError, "unavailable"
    profile = SchoolProfile.for(Card.new(school_id: "School fl-96528", profile: {}), refresh: true, client: client)
    assert_equal "Bluewater Charter School", profile.source["name"]
    assert_includes profile.programs["Academic clubs"], "Book / reading club"
  end

  test "missing optional data stays unavailable and existing student group numbers stay ratings" do
    profile = SchoolProfile.new(Card.new, {})
    assert_empty profile.student_group_ratings
    assert_nil profile.application_deadline_date
    assert_empty profile.english_learning_support
    assert_empty profile.review_topics
    assert profile.support_programs.values.all?(&:empty?)
    profile = SchoolProfile.new(Card.new, { "test_scores_rating_white" => 8, "test_scores_rating_asian" => nil })
    assert_equal({ "White students" => 8 }, profile.student_group_ratings)
  end

  test "external school links accept valid websites and suppress placeholders and unsafe schemes" do
    profile = SchoolProfile.new(Card.new, { "osp" => {
      "school_url" => ["https://school.test"], "admissions_url" => ["javascript:alert(1)"],
      "facebook_url" => ["https://www.example.org/school/social"]
    } })
    assert_equal "https://school.test", profile.website
    assert_nil profile.admissions_url
    assert_nil profile.facebook_url
  end
end
