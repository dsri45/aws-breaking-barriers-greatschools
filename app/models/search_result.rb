# Read-only view of one guided-search turn: extracted criteria, the chat
# transcript, and ranked results. Today it is loaded from the sample fixture
# (db/sample/results.json); the agent's `present_results` tool will return
# the same shape. See docs/card_contract.md.
class SearchResult
  STATUSES = %w[confirmed partial needs_attention missing].freeze

  Criterion = Data.define(:key, :label, :importance)
  Evidence  = Data.define(:key, :label, :status, :evidence, :as_of)
  Pin       = Data.define(:name, :rating, :lat, :lon, :kind)

  School = Data.define(:school_id, :rank_label, :name, :entity_type, :grades,
                       :distance_mi, :summary_rating, :avg_review_rating,
                       :review_count, :review_topic, :why, :lat, :lon,
                       :saved, :criteria) do
    def rated? = !summary_rating.nil?
  end

  attr_reader :query, :criteria, :messages, :schools, :unmatched

  def self.sample
    new(JSON.parse(Rails.root.join("db/sample/results.json").read))
  end

  def initialize(data)
    @query     = data.fetch("query")
    @criteria  = data.fetch("criteria").map { |c| Criterion.new(**c.symbolize_keys) }
    @messages  = data.fetch("messages")
    @schools   = data.fetch("results").map { |r| build_school(r) }
    @unmatched = data.fetch("nearby_unmatched", []).map do |u|
      lat, lon = parse_latlon(u["latlon"])
      Pin.new(name: u["name"], rating: u["summary_rating"], lat:, lon:, kind: :other)
    end
  end

  def pins
    schools.each_with_index.map do |s, i|
      Pin.new(name: s.name, rating: s.summary_rating, lat: s.lat, lon: s.lon,
              kind: i.zero? ? :selected : :match)
    end + unmatched
  end

  private

  def build_school(r)
    lat, lon = parse_latlon(r["latlon"])
    evidence = r.fetch("criteria").map do |c|
      raise ArgumentError, "unknown status #{c['status']}" unless STATUSES.include?(c["status"])
      Evidence.new(key: c["key"], label: c["label"], status: c["status"],
                   evidence: c["evidence"], as_of: c["as_of"] && Date.parse(c["as_of"]))
    end
    School.new(school_id: r["school_id"], rank_label: r["rank_label"], name: r["name"],
               entity_type: r["entity_type"], grades: r["grades"], distance_mi: r["distance_mi"],
               summary_rating: r["summary_rating"], avg_review_rating: r["avg_review_rating"],
               review_count: r["review_count"], review_topic: r["review_topic"], why: r["why"],
               lat:, lon:, saved: r["saved"], criteria: evidence)
  end

  # The GreatSchools sample data stores coordinates as "lat, lon" strings.
  def parse_latlon(str) = str.split(",").map { |v| Float(v.strip) }
end
