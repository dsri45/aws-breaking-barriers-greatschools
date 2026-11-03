module GuidedSearch
  # Blends two result legs (BM25 and k-NN) in Ruby. Each leg's scores are
  # min-max normalized to 0..1, then combined as a weighted sum:
  #
  #   score = alpha * bm25_norm + (1 - alpha) * knn_norm
  #
  # alpha = 1.0 is pure BM25 order; alpha = 0.0 is pure k-NN order. Documents
  # present in only one leg contribute 0 for the missing leg. Results are
  # re-sorted by the blended score and truncated to `size`.
  module HybridRanker
    module_function

    # @param bm25_hits [Array<Hash>] { "id", "score", "source" }
    # @param knn_hits  [Array<Hash>] { "id", "score", "source" }
    # @return [Array<Hash>] { "id", "score", "bm25", "knn", "source" }
    def blend(bm25_hits, knn_hits, alpha: 0.5, size: 10)
      bm25_norm = normalize_scores(bm25_hits)
      knn_norm  = normalize_scores(knn_hits)

      sources = {}
      bm25_hits.each { |hit| sources[hit["id"]] ||= hit["source"] }
      knn_hits.each  { |hit| sources[hit["id"]] ||= hit["source"] }

      ids = (bm25_norm.keys + knn_norm.keys).uniq
      blended = ids.map do |id|
        bm25 = bm25_norm[id] || 0.0
        knn  = knn_norm[id] || 0.0
        {
          "id" => id,
          "score" => (alpha * bm25) + ((1 - alpha) * knn),
          "bm25" => bm25,
          "knn" => knn,
          "source" => sources[id]
        }
      end

      blended.sort_by { |hit| -hit["score"] }.first(size)
    end

    # Min-max normalize a leg's raw scores into 0..1 by id.
    # If all scores are equal (or a single hit), each maps to 1.0.
    def normalize_scores(hits)
      return {} if hits.empty?

      scores = hits.map { |hit| hit["score"].to_f }
      min = scores.min
      max = scores.max
      range = max - min

      hits.each_with_object({}) do |hit, out|
        out[hit["id"]] = range.zero? ? 1.0 : (hit["score"].to_f - min) / range
      end
    end
  end
end
