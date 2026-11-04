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
    "Sports" => %w[boys_sports girls_sports],
    "College preparation" => %w[college_prep_curriculum],
    "College guidance" => %w[college_prep_support],
    "Career exploration" => %w[career_prep]
  }.freeze
  SUPPORT_GROUPS = {
    "Mental health supports" => %w[mental_health],
    "Culturally responsive practices" => %w[cultural_responsiveness],
    "Family engagement" => %w[family_engagement]
  }.freeze
  GROUP_RATING_FIELDS = {
    "test_scores_rating_african_american" => "African American students",
    "test_scores_rating_asian" => "Asian students",
    "test_scores_rating_hispanic" => "Hispanic students",
    "test_scores_rating_two_or_more_races" => "Students of two or more races",
    "test_scores_rating_white" => "White students"
  }.freeze
  VALUE_LABELS = {
    "STEM" => "STEM", "college_prep" => "College preparatory", "cte" => "Career and technical education",
    "ell" => "English language learning", "jrotc" => "JROTC", "sms_email" => "Text and email updates",
    "parent_teacher_conf" => "Parent-teacher conferences", "prof_development" => "Teacher professional development",
    "busses" => "Bus service", "day" => "Day school", "coed" => "Coed", "uniform" => "Uniforms",
    "book_club" => "Book / reading club", "pe_classes" => "Physical education classes",
    "staff_training_mental" => "Staff training on mental health", "website_apps" => "Website and app updates"
  }.freeze

  attr_reader :school, :source

  def self.for(school, refresh: false, client: nil)
    source = (seed_schools[school.school_id] || {}).deep_merge(school.profile || {})
    if (refresh || source.empty?) && (client || ENV["OPENSEARCH_URL"].present?)
      begin
        client ||= GuidedSearch::OpenSearch.new
        complete_source = client.request("GET", "/schools/_doc/#{ERB::Util.url_encode(school.school_id)}")&.fetch("_source", nil)
        source = complete_source if complete_source.is_a?(Hash)
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

  def website = external_url("school_url")
  def admissions_url = external_url("admissions_url")
  def facebook_url = external_url("facebook_url")

  def external_url(field)
    url = osp(field).first
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
      ("Career preparation" if source.dig("career_prep", "qualifies") == true),
      ("English learning support" if source.dig("ell", "qualifies") == true)
    ].compact
  end

  def programs
    academic = Array(source["ap_courses"]).map { |course| "AP #{course}" }
    academic.unshift("Gifted & Talented program") if source["gifted_talented"] == true
    academic << "IB offered" if source["ib_offered"] == true
    academic.concat(Array(source["ib_programs"]).grep(String))
    groups = { "Academic programs" => academic }
    after_school = (Array(source["after_school_clubs"]) + osp("after_school_clubs")).grep(String).map(&:strip).compact_blank
    if after_school.any?
      groups["After-school clubs"] = after_school.map { |club| VALUE_LABELS.fetch(club) { club.tr("_", " ").humanize } }.uniq
    end
    OSP_GROUPS.each do |label, fields|
      groups[label] = labels_for(fields)
    end
    groups
  end

  def support_programs
    SUPPORT_GROUPS.transform_values { |fields| labels_for(fields) }
  end

  def student_group_ratings
    GROUP_RATING_FIELDS.filter_map { |field, label| [label, source[field]] unless source[field].nil? }.to_h
  end

  def application_requirements = labels_for(%w[application_requirements])
  def application_deadline = osp("application_deadline_date").first

  def application_deadline_date
    value = application_deadline.to_s
    value.match?(/\A\d{1,2}\/\d{1,2}\/\d{4}\z/) ? Date.strptime(value, "%m/%d/%Y") : Date.iso8601(value)
  rescue Date::Error
    nil
  end

  def english_learning_support
    source["ell"].is_a?(Hash) ? source["ell"] : {}
  end

  def review_topics
    topics = source.dig("sentiment_stats", "sentiment_by_topic")
    return {} unless topics.is_a?(Hash)

    topics.select { |topic, counts| topic != "Other" && counts.is_a?(Hash) && counts["total"].to_i.positive? }
  end

  def school_info
    {
      "District" => district, "County" => source["county"],
      "School type" => labels_for(%w[school_sub_type]).join(", "),
      "School leader" => leader, "Fax" => osp("school_fax").first,
      "Start time" => osp("start_time").first, "End time" => osp("end_time").first,
      "Schedule" => labels_for(%w[schedule]).join(", "),
      "Transportation" => labels_for(%w[transportation]).join(", "),
      "Dress code" => labels_for(%w[dress_code]).join(", "),
      "Day or boarding" => labels_for(%w[boarding]).join(", "),
      "Coed / single-gender" => labels_for(%w[coed]).join(", ")
    }.compact_blank
  end

  def updated_on
    Date.iso8601(source["created"].to_s)
  rescue Date::Error
    nil
  end

  private

  def labels_for(fields)
    fields.flat_map { |field| osp(field) }.map { |value| VALUE_LABELS.fetch(value) { value.tr("_", " ").humanize } }.uniq
  end

  def osp(field)
    Array(source.dig("osp", field)).grep(String).map(&:strip).compact_blank
  end
end
