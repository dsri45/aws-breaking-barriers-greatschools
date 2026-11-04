module GuidedSearch
  # Production retriever for GuidedSearch::Turn, a drop-in replacement for
  # DemoSearch. Enable with:
  #
  #   GUIDED_SEARCH_RETRIEVER=GuidedSearch::OpenSearchRetriever
  #
  # Given the agent's extracted `preferences`, it runs hybrid school search,
  # scores evidence in Ruby (EvidenceScorer), and returns ranked cards in the
  # shape of db/sample/results.json (see docs/card_contract.md). The agent
  # still writes `why` and `rank_label`; this fills safe defaults so the page
  # renders without them.
  #
  # Expected `preferences` (all optional; produced by the agent's
  # extract_criteria):
  #   "query"     => original parent text (free-text wish)
  #   "criteria"  => [{ "key", "label", "importance" }, ...]
  #   "filters"   => SchoolSearch filters (state, city, level_codes, ...)
  #   "geo"       => { "lat", "lon", "radius_km" }
  #   "size"      => result count
  class OpenSearchRetriever
    DEFAULT_SIZE = 5

    def initialize(school_search: GuidedSearch::SchoolSearch.new)
      @school_search = school_search
    end

    # @return [Array<Hash>] card hashes (string keys), ranked best-first
    def call(preferences:)
      prefs = preferences || {}
      criteria = Array(prefs["criteria"])
      geo = symbolize_geo(prefs["geo"])
      size = (prefs["size"] || DEFAULT_SIZE).to_i

      filters = symbolize(prefs["filters"])
      required_keys = criteria.select { |criterion| criterion["importance"] == "require" }.pluck("key") - %w[level location]
      hits = @school_search.search(
        text: prefs["query"].to_s,
        filters: filters,
        geo: geo,
        size: required_keys.empty? ? size : size * GuidedSearch::SchoolSearch::CANDIDATE_MULTIPLIER
      )

      # Thread the requested grade level into evidence scoring so a "middle
      # school" requirement reads correctly against each school's level_codes.
      context = { level: filters[:level_codes] }.compact
      cards = hits.lazy.map { |hit| card(hit, criteria, geo, context) }
      return cards.first(size) if required_keys.empty?

      cards.select do |result|
        confirmed_keys = result["criteria"].select { |evidence| evidence["status"] == "confirmed" }.pluck("key")
        (required_keys - confirmed_keys).empty?
      end.first(size)
    end

    private

    def card(hit, criteria, geo, context = {})
      source = hit["source"] || {}
      evidence = GuidedSearch::EvidenceScorer.score(school: source, criteria: criteria, context: context)

      {
        "school_id" => source["id"],
        "rank_label" => nil,                 # agent writes this
        "name" => source["name"],
        "entity_type" => source["entity_type"],
        "grades" => grades(source["level_codes"]),
        "distance_mi" => distance_mi(source["location"], geo),
        "summary_rating" => source["summary_rating"], # int or nil (never faked)
        "avg_review_rating" => source["avg_review_rating"],
        "review_count" => source.dig("sentiment_stats", "total_reviews"),
        "review_topic" => review_topic(source),
        "why" => nil,                        # agent writes this
        "latlon" => source["latlon"],
        "saved" => false,
        "criteria" => evidence,
        "profile" => source.except("embedding", "reviews_text", "reviews_positive", "reviews_negative")
      }
    end

    def review_topic(source)
      GuidedSearch::EvidenceScorer.new(source).review_topic
    end

    def grades(level_codes)
      names = { "p" => "PK", "e" => "K-5", "m" => "6-8", "h" => "9-12" }
      Array(level_codes).map { |code| names.fetch(code, code) }.join(", ")
    end

    # Great-circle distance in miles between the school and the search point.
    def distance_mi(location, geo)
      return nil unless location.is_a?(Hash) && geo && geo[:lat] && geo[:lon]

      haversine_mi(location["lat"], location["lon"], geo[:lat], geo[:lon]).round(1)
    end

    def haversine_mi(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180
      r = 3958.8 # Earth radius in miles
      dlat = (lat2 - lat1) * rad
      dlon = (lon2 - lon1) * rad
      a = (Math.sin(dlat / 2)**2) +
          (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlon / 2)**2))
      2 * r * Math.asin(Math.sqrt(a))
    end

    def symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
    end

    def symbolize_geo(geo)
      return nil unless geo.is_a?(Hash)

      { lat: geo["lat"] || geo[:lat], lon: geo["lon"] || geo[:lon],
        radius_km: geo["radius_km"] || geo[:radius_km] }
    end
  end
end
