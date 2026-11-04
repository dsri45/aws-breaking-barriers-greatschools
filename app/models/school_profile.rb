class SchoolProfile
  RATING_FIELDS = {
    "test_scores_rating" => "Test scores",
    "student_progress_rating" => "Student progress",
    "college_readiness_rating" => "College readiness",
    "low_income_rating" => "Low-income students",
    "swd_test_scores_rating" => "Students with disabilities"
  }.freeze
  OSP_GROUPS = {
    "Academic clubs" => %w[student_clubs],
    "Arts" => %w[arts_visual arts_music arts_performing_written],
    "Languages" => %w[foreign_language],
    "Sports" => %w[boys_sports girls_sports]
  }.freeze

  attr_reader :school, :source

  def self.for(school)
    source = school.profile.presence
    source ||= seed_schools[school.school_id]
    if source.nil? && ENV["OPENSEARCH_URL"].present?
      begin
        source = GuidedSearch::OpenSearch.new.request("GET", "/schools/_doc/#{ERB::Util.url_encode(school.school_id)}")&.fetch("_source", nil)
      rescue GuidedSearch::UpstreamError => error
        Rails.logger.warn("School profile unavailable (#{error.message})")
      end
    end
    new(school, source || {})
  end

  def self.seed_schools
    @seed_schools ||= JSON.parse(Rails.root.join("db/seeds/school_data.json").read).index_by { |school| school["id"].to_s }
  end

  def initialize(school, source)
    @school = school
    @source = source
  end

  def address
    street = source["street"].presence || osp("address").first
    locality = [source["city"], [source["state"], source["zipcode"]].compact_blank.join(" ")].compact_blank.join(", ")
    [street, locality].compact_blank.join(", ")
  end

  def city_state
    [source["city"], source["state"]].compact_blank.join(", ")
  end

  def district = source["school_district_name"]
  def enrollment = source["enrollment"]
  def phone = osp("school_phone").first
  def leader = osp("administrator_name").first
  def leader_email = osp("administrator_email").first
  def description = Array(source["esp_text"]).compact_blank
  def rating_factors = source.slice(*RATING_FIELDS.keys).compact
  def reviews = Array(source["reviews_full"])

  def website
    url = osp("school_url").first
    uri = URI.parse(url.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
    return if uri.host.match?(/(?:\A|\.)example\.(?:com|net|org)\z/i)

    url
  rescue URI::InvalidURIError
    nil
  end

  def rating_label(rating = school.summary_rating)
    return "Not rated" if rating.nil?
    return "Above average" if rating >= 8
    return "Average" if rating >= 5

    "Below average"
  end

  def highlights
    [
      ("Gifted & Talented program" if source["gifted_talented"] == true),
      ("Small class sizes" if source.dig("class_size", "qualifies") == true),
      ("High attendance" if source.dig("high_attendance", "qualifies") == true),
      ("Career preparation" if source.dig("career_prep", "qualifies") == true)
    ].compact
  end

  def programs
    academic = Array(source["ap_courses"]).map { |course| "AP #{course}" }
    academic.unshift("Gifted & Talented program") if source["gifted_talented"] == true
    groups = { "Academic programs" => academic }
    OSP_GROUPS.each do |label, fields|
      groups[label] = fields.flat_map { |field| osp(field) }.map { |value| value.tr("_", " ").humanize }.uniq
    end
    groups
  end

  def school_info
    {
      "District" => district, "County" => source["county"],
      "School leader" => leader, "School hours" => [osp("start_time").first, osp("end_time").first].compact_blank.join(" – "),
      "Transportation" => osp("transportation").map(&:humanize).join(", "),
      "Dress code" => osp("dress_code").map { |value| value.tr("_", " ").humanize }.join(", "),
      "School setting" => osp("boarding").map(&:humanize).join(", ")
    }.compact_blank
  end

  def updated_on
    Date.iso8601(source["created"].to_s)
  rescue Date::Error
    nil
  end

  private

  def osp(field)
    Array(source.dig("osp", field)).compact_blank
  end
end
