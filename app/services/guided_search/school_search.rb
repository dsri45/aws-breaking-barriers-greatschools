module GuidedSearch
  # Hybrid search over the `schools` index: a BM25 + filters leg and a k-NN
  # vector leg, with scores normalized and blended in Ruby (no OpenSearch
  # search pipeline dependency). Returns raw documents with scores; evidence
  # scoring and card shaping happen above this class.
  #
  # Criteria (all keys optional):
  #   text:   free-text wish (drives BM25 and the k-NN query vector)
  #   filters: { state:, city:, zipcode:, entity_type:, level_codes:,
  #              gifted_talented:, min_summary_rating:, max_summary_rating:,
  #              min_avg_review_rating: }
  #   geo:     { lat:, lon:, radius_km: }
  #   size:    result count (default 10)
  #   alpha:   blend weight, 1.0 = pure BM25, 0.0 = pure k-NN (default 0.5)
  #
  # Null handling: a rating threshold matches only documents that HAVE the
  # field in range; schools with an absent rating are simply not matched, never
  # ranked low for missing data.
  class SchoolSearch
    INDEX = "schools".freeze
    DEFAULT_SIZE = 10
    DEFAULT_ALPHA = 0.5
    CANDIDATE_MULTIPLIER = 3

    def initialize(client: GuidedSearch::OpenSearch.new, embeddings: GuidedSearch::Embeddings.new)
      @client = client
      @embeddings = embeddings
    end

    # Hybrid search. @return [Array<Hash>] { "id", "score", "bm25", "knn", "source" }
    def search(criteria = {})
      criteria = deep_symbolize(criteria)
      size = (criteria[:size] || DEFAULT_SIZE).to_i
      alpha = criteria.key?(:alpha) ? criteria[:alpha].to_f : DEFAULT_ALPHA
      candidate_k = size * CANDIDATE_MULTIPLIER

      bm25_hits = bm25(criteria, size: candidate_k)
      knn_hits  = criteria[:text].to_s.strip.empty? ? [] : knn(criteria, size: candidate_k)

      GuidedSearch::HybridRanker.blend(bm25_hits, knn_hits, alpha: alpha, size: size)
    end

    # BM25 + filters leg. @return [Array<Hash>] { "id", "score", "source" }
    def bm25(criteria, size: DEFAULT_SIZE)
      criteria = deep_symbolize(criteria)
      run(size: size, query: bm25_query(criteria))
    end

    # k-NN vector leg (embeds criteria[:text]). @return [Array<Hash>]
    def knn(criteria, size: DEFAULT_SIZE)
      criteria = deep_symbolize(criteria)
      text = criteria[:text].to_s.strip
      return [] if text.empty?

      vector = @embeddings.embed(text)
      filter = build_filters(criteria)
      knn_clause = { embedding: { vector: vector, k: size } }
      knn_clause[:embedding][:filter] = { bool: { filter: filter } } unless filter.empty?

      run(size: size, query: { knn: knn_clause })
    end

    private

    def bm25_query(criteria)
      filters = build_filters(criteria)
      shoulds = build_shoulds(criteria)
      text = criteria[:text].to_s.strip

      must =
        if text.empty?
          [{ match_all: {} }]
        else
          [{ multi_match: { query: text,
                            fields: ["name^3", "esp_text^2", "reviews_text", "reviews_positive", "city"],
                            type: "best_fields" } }]
        end

      { bool: { must: must, filter: filters, should: shoulds } }
    end

    def build_filters(criteria)
      filter = criteria[:filters] || {}
      geo = criteria[:geo]
      clauses = []

      clauses << term_or_terms(:state, filter[:state])
      clauses << term_or_terms(:city_untokenized, filter[:city])
      clauses << term_or_terms(:zipcode, filter[:zipcode])
      clauses << term_or_terms(:entity_type, filter[:entity_type])
      clauses << term_or_terms(:level_codes, filter[:level_codes])
      clauses << ({ term: { gifted_talented: filter[:gifted_talented] } } unless filter[:gifted_talented].nil?)

      rating = {}
      rating[:gte] = filter[:min_summary_rating] if filter[:min_summary_rating]
      rating[:lte] = filter[:max_summary_rating] if filter[:max_summary_rating]
      clauses << { range: { summary_rating: rating } } unless rating.empty?

      if filter[:min_avg_review_rating]
        clauses << { range: { avg_review_rating: { gte: filter[:min_avg_review_rating] } } }
      end

      if geo && geo[:lat] && geo[:lon]
        clauses << { geo_distance: { distance: "#{geo[:radius_km] || 25}km",
                                     location: { lat: geo[:lat], lon: geo[:lon] } } }
      end

      clauses.compact
    end

    def build_shoulds(criteria)
      boosts = criteria[:boosts] || {}
      shoulds = []
      if boosts[:min_avg_review_rating]
        shoulds << { range: { avg_review_rating: { gte: boosts[:min_avg_review_rating], boost: 2.0 } } }
      end
      shoulds
    end

    def term_or_terms(field, value)
      return nil if value.nil?

      value.is_a?(Array) ? { terms: { field => value } } : { term: { field => value } }
    end

    def run(body)
      response = @client.request("POST", "/#{INDEX}/_search", body: body)
      Array(response&.dig("hits", "hits")).map do |hit|
        { "id" => hit["_id"], "score" => hit["_score"], "source" => hit["_source"] }
      end
    end

    def deep_symbolize(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), out| out[k.to_sym] = deep_symbolize(v) }
      when Array then value.map { |item| deep_symbolize(item) }
      else value
      end
    end
  end
end
