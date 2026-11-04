# Read-only view of one guided-search turn: extracted criteria, the chat
# transcript, and ranked results. See docs/card_contract.md.
class SearchResult
  STATUSES = %w[confirmed partial needs_attention missing].freeze

  Criterion = Data.define(:key, :label, :importance)
  Evidence  = Data.define(:key, :label, :status, :evidence, :as_of)
  Pin       = Data.define(:name, :rating, :lat, :lon, :kind)

  School = Data.define(:school_id, :rank_label, :name, :entity_type, :grades,
                       :distance_mi, :summary_rating, :avg_review_rating,
                       :review_count, :review_topic, :why, :lat, :lon,
                       :saved, :criteria, :profile) do
    def rated? = !summary_rating.nil?
  end

  attr_reader :query, :grade_level, :criteria, :messages, :schools, :unmatched

  def self.sample
    new(JSON.parse(Rails.root.join("db/sample/results.json").read))
  end

  def self.from_session(search_session, shortlist:, show_shortlist:)
    preferences = search_session&.preferences || {}
    messages = Array(search_session&.history).map do |message|
      { "role" => message.fetch("role"), "text" => message.fetch("content") }
    end
    latest_reply = messages.last&.fetch("text").to_s
    Array(search_session&.follow_up_questions).each do |question|
      next if latest_reply.include?(question)

      messages << { "role" => "question", "text" => question, "options" => [] }
    end

    saved_ids = shortlist.map(&:school_id).to_set
    schools = show_shortlist ? shortlist.map(&:school) : Array(search_session&.results)
    new(
      "query" => preferences["query"],
      "grade_level" => preferences["grade_level"],
      "criteria" => Array(preferences["criteria"]),
      "messages" => messages,
      "results" => schools.map do |school|
        id = (school["id"] || school["school_id"]).to_s
        school.merge("school_id" => id, "saved" => saved_ids.include?(id))
      end
    )
  end

  def initialize(data)
    @query     = data.fetch("query")
    @grade_level = data["grade_level"]
    @criteria  = data.fetch("criteria").map { |c| Criterion.new(**c.symbolize_keys) }
    @messages  = data.fetch("messages")
    @schools   = data.fetch("results").map { |r| build_school(r) }
    @unmatched = data.fetch("nearby_unmatched", []).map do |u|
      lat, lon = parse_latlon(u["latlon"])
      Pin.new(name: u["name"], rating: u["summary_rating"], lat:, lon:, kind: :other)
    end
  end

  def pins
    schools.each_with_index.filter_map do |s, i|
      next unless s.lat && s.lon

      Pin.new(name: s.name, rating: s.summary_rating, lat: s.lat, lon: s.lon,
              kind: i.zero? ? :selected : :match)
    end + unmatched
  end

  private

  def build_school(r)
    lat, lon = parse_latlon(r["latlon"] || [r["latitude"], r["longitude"]].join(","))
    evidence = Array(r["criteria"] || r["evidence"]).map do |c|
      raise ArgumentError, "unknown status #{c['status']}" unless STATUSES.include?(c["status"])
      Evidence.new(key: c["key"] || c["criterion"], label: c["label"] || c["criterion"], status: c["status"],
                   evidence: c["evidence"] || c["source"], as_of: c["as_of"] && Date.parse(c["as_of"]))
    end
    School.new(school_id: r["school_id"], rank_label: r["rank_label"], name: r["name"],
               entity_type: r["entity_type"], grades: r["grades"], distance_mi: r["distance_mi"],
               summary_rating: r["summary_rating"], avg_review_rating: r["avg_review_rating"],
               review_count: r["review_count"], review_topic: r["review_topic"], why: r["why"],
               lat:, lon:, saved: r["saved"], criteria: evidence, profile: r["profile"] || {})
  end

  # The GreatSchools sample data stores coordinates as "lat, lon" strings.
  def parse_latlon(str)
    str.to_s.split(",").map { |value| Float(value.strip, exception: false) }
  end
end
