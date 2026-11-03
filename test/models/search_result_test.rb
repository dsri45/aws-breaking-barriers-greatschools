require "test_helper"

class SearchResultTest < ActiveSupport::TestCase
  test "loads the sample fixture in the card contract shape" do
    search = SearchResult.sample
    assert_equal 3, search.schools.size
    assert_equal 5, search.criteria.size
    oak = search.schools.first
    assert oak.rated?
    assert_in_delta 34.1015, oak.lat
    assert_equal %w[confirmed partial missing], oak.criteria.map(&:status)
  end

  test "a school with a null rating is unrated, not low-rated" do
    refute SearchResult.sample.schools.last.rated?
  end

  test "rejects unknown evidence statuses" do
    data = JSON.parse(Rails.root.join("db/sample/results.json").read)
    data["results"][0]["criteria"][0]["status"] = "great"
    assert_raises(ArgumentError) { SearchResult.new(data) }
  end
end
