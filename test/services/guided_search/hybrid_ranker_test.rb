require "test_helper"

module GuidedSearch
  class HybridRankerTest < ActiveSupport::TestCase
    def hit(id, score)
      { "id" => id, "score" => score, "source" => { "id" => id } }
    end

    test "a doc strong in both legs outranks docs strong in only one" do
      bm25 = [hit("both", 10), hit("bm25only", 9)]
      knn  = [hit("both", 0.9), hit("knnonly", 0.8)]
      ranked = HybridRanker.blend(bm25, knn, alpha: 0.5, size: 10)
      assert_equal "both", ranked.first["id"]
    end

    test "alpha 1.0 reduces to pure BM25 ordering" do
      bm25 = [hit("a", 10), hit("b", 1)]
      knn  = [hit("b", 0.9), hit("a", 0.1)]
      ranked = HybridRanker.blend(bm25, knn, alpha: 1.0, size: 10)
      assert_equal %w[a b], ranked.map { |h| h["id"] }
    end

    test "alpha 0.0 reduces to pure k-NN ordering" do
      bm25 = [hit("a", 10), hit("b", 1)]
      knn  = [hit("b", 0.9), hit("a", 0.1)]
      ranked = HybridRanker.blend(bm25, knn, alpha: 0.0, size: 10)
      assert_equal %w[b a], ranked.map { |h| h["id"] }
    end

    test "truncates to size" do
      bm25 = (1..10).map { |i| hit("s#{i}", i) }
      assert_equal 3, HybridRanker.blend(bm25, [], alpha: 1.0, size: 3).size
    end

    test "carries source through and reports leg scores" do
      ranked = HybridRanker.blend([hit("x", 5)], [hit("x", 0.5)], alpha: 0.5, size: 1)
      row = ranked.first
      assert_equal({ "id" => "x" }, row["source"])
      assert_in_delta 1.0, row["bm25"], 1e-9
      assert_in_delta 1.0, row["knn"], 1e-9
    end
  end
end
