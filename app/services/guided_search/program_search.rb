module GuidedSearch
  # Hybrid search over the `programs` index, reusing HybridRanker. Program
  # filters cover type, tags, age range, and geo. Instance status and dates are
  # carried through in the source so callers can flag past (stale) sessions.
  #
  # Criteria (all optional):
  #   text:   free-text wish (BM25 + k-NN query vector)
  #   filters: { program_type:, tag_names:, state:, city:, zipcode:, age: }
  #            `age` matches programs whose age_min_search <= age <= age_max_search
  #   geo:     { lat:, lon:, radius_km: }
  #   size:, alpha: (same semantics as SchoolSearch)
  class ProgramSearch
    INDEX = "programs".freeze
    DEFAULT_SIZE = 10
    DEFAULT_ALPHA = 0.5
    CANDIDATE_MULTIPLIER = 3

    def initialize(client: GuidedSearch::OpenSearch.new, embeddings: GuidedSearch::Embeddings.new)
      @client = client
      @embeddings = embeddings
    end

    def search(criteria = {})
      criteria = deep_symbolize(criteria)
      size = (criteria[:size] || DEFAULT_SIZE).to_i
      alpha = criteria.key?(:alpha) ? criteria[:alpha].to_f : DEFAULT_ALPHA
      candidate_k = size * CANDIDATE_MULTIPLIER

      bm25_hits = bm25(criteria, size: candidate_k)
      knn_hits  = criteria[:text].to_s.strip.empty? ? [] : knn(criteria, size: candidate_k)

      GuidedSearch::HybridRanker.blend(bm25_hits, knn_hits, alpha: alpha, size: size)
    end

    def bm25(criteria, size: DEFAULT_SIZE)
      criteria = deep_symbolize(criteria)
      run(size: size, query: bm25_query(criteria))
    end

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
      text = criteria[:text].to_s.strip

      must =
        if text.empty?
          [{ match_all: {} }]
        else
          [{ multi_match: { query: text,
                            fields: ["name^3", "description^2", "tag_names"],
                            type: "best_fields" } }]
        end

      { bool: { must: must, filter: filters } }
    end

    def build_filters(criteria)
      filter = criteria[:filters] || {}
      geo = criteria[:geo]
      clauses = []

      clauses << term_or_terms(:program_type, filter[:program_type])
      clauses << term_or_terms(:tag_names, filter[:tag_names])
      clauses << term_or_terms(:state, filter[:state])
      clauses << term_or_terms(:city, filter[:city])
      clauses << term_or_terms(:zipcode, filter[:zipcode])

      if filter[:age]
        clauses << { range: { age_min_search: { lte: filter[:age] } } }
        clauses << { range: { age_max_search: { gte: filter[:age] } } }
      end

      if geo && geo[:lat] && geo[:lon]
        clauses << { geo_distance: { distance: "#{geo[:radius_km] || 25}km",
                                     location: { lat: geo[:lat], lon: geo[:lon] } } }
      end

      clauses.compact
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
