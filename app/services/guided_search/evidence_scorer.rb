module GuidedSearch
  # Scores a school document against the parent's criteria, in Ruby, from the
  # school's own fields. Per docs/card_contract.md, this keeps evidence honest:
  # the model only writes `why`/`rank_label`/chat, never the status.
  #
  # Each criterion becomes an evidence row:
  #   { key:, label:, status:, evidence:, as_of: }
  #   status in: confirmed | partial | needs_attention | missing
  #   as_of:    ISO date string (or nil) for the datum behind the status;
  #             the UI badges data older than 12 months.
  #
  # A key rule from the contract and the data: a NULL/absent rating is `missing`
  # ("no data published"), never a low score. Absent fields never produce
  # `needs_attention` on their own.
  class EvidenceScorer
    STATUSES = %w[confirmed partial needs_attention missing].freeze

    # @param school [Hash] a school _source document
    # @param criteria [Array<Hash>] [{ "key"=>, "label"=>, "importance"=> }, ...]
    # @param context [Hash] optional extras, e.g. { after_school_needed_until: "18:00" }
    # @return [Array<Hash>] evidence rows in criteria order
    def self.score(school:, criteria:, context: {})
      new(school, context).score(criteria)
    end

    def initialize(school, context = {})
      @school = school || {}
      @context = context || {}
    end

    def score(criteria)
      Array(criteria).map { |criterion| row(stringify(criterion)) }
    end

    # Public: the dominant review topic and its mood, e.g.
    # "Teachers / Staff: mostly positive", or nil when there is no signal.
    # Used for the card's `review_topic`.
    def review_topic
      dominant_topic
    end

    private

    def row(criterion)
      key = criterion["key"].to_s
      label = criterion["label"] || key.titleize
      result =
        case key
        when "high_performing", "rating", "summary_rating" then rating_evidence
        when "level", "grade", "grades"                    then level_evidence(criterion)
        when "reviews", "well_reviewed", "review"          then review_evidence
        when "gifted", "gifted_talented"                   then boolean_field_evidence("gifted_talented")
        when "ap", "ap_courses"                            then ap_evidence
        when "busing", "transportation"                    then osp_evidence("transportation", "Bus service")
        when "arts", "arts_visual"                         then osp_evidence("arts_visual", "Visual arts")
        when "class_size", "small_classes"                then tiered_object_evidence("class_size", "Class size")
        when "attendance", "high_attendance"              then tiered_object_evidence("high_attendance", "Attendance")
        when "career_prep"                                 then tiered_object_evidence("career_prep", "Career prep")
        else generic_presence_evidence(key)
        end

      { "key" => key, "label" => label }.merge(result)
    end

    # ---- rating: null => missing (never low) --------------------------------

    def rating_evidence
      rating = @school["summary_rating"]
      return finding("missing", "No rating published", nil) if rating.nil?

      status = rating >= 8 ? "confirmed" : (rating >= 5 ? "partial" : "needs_attention")
      finding(status, "GreatSchools summary rating #{rating}/10", nil)
    end

    # ---- grade level --------------------------------------------------------

    def level_evidence(criterion)
      levels = Array(@school["level_codes"])
      return finding("missing", "No grade levels published", nil) if levels.empty?

      wanted = Array(@context[:level] || criterion["value"]).map(&:to_s)
      names = levels.map { |code| level_name(code) }.join(", ")
      if wanted.empty?
        finding("confirmed", "Serves #{names}", nil)
      elsif (wanted & levels).any?
        finding("confirmed", "Serves #{names}", nil)
      else
        finding("needs_attention", "Serves #{names}, not the requested level", nil)
      end
    end

    # ---- review quality: rating + dominant sentiment topic ------------------

    def review_evidence
      avg = @school["avg_review_rating"]
      count = @school.dig("sentiment_stats", "total_reviews")
      return finding("missing", "No reviews yet", nil) if avg.nil? || avg.to_f.zero? || count.to_i.zero?

      topic = dominant_topic
      detail = "#{count} reviews, avg #{avg}/5"
      detail += "; #{topic}" if topic
      status = avg.to_f >= 4.0 ? "confirmed" : (avg.to_f >= 3.0 ? "partial" : "needs_attention")
      finding(status, detail, nil)
    end

    # ---- boolean feature ----------------------------------------------------

    def boolean_field_evidence(field)
      value = @school[field]
      return finding("missing", "No data published", nil) if value.nil?

      value ? finding("confirmed", "Offered", nil) : finding("needs_attention", "Not offered", nil)
    end

    def ap_evidence
      courses = Array(@school["ap_courses"])
      return finding("missing", "No AP course data published", nil) if courses.empty?

      finding("confirmed", "#{courses.size} AP courses incl. #{courses.first(3).join(', ')}", nil)
    end

    # ---- osp keyword presence ----------------------------------------------

    def osp_evidence(osp_key, label)
      values = Array(@school.dig("osp", osp_key))
      return finding("missing", "No #{label.downcase} data published", nil) if values.empty?

      finding("confirmed", "#{label}: #{values.join(', ')}", nil)
    end

    # ---- tiered object with a date (class_size, high_attendance, ...) -------

    def tiered_object_evidence(field, label)
      obj = @school[field]
      return finding("missing", "No #{label.downcase} data published", nil) unless obj.is_a?(Hash)

      tier = obj["tier"]
      qualifies = obj["qualifies"]
      as_of = obj["source_generated_at"]
      status = qualifies ? "confirmed" : "partial"
      detail = "#{label}: #{tier}".strip
      finding(status, detail, as_of)
    end

    # ---- fallback -----------------------------------------------------------

    def generic_presence_evidence(key)
      value = @school[key]
      if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        finding("missing", "No data published", nil)
      else
        finding("partial", "Data present", nil)
      end
    end

    # ---- helpers ------------------------------------------------------------

    def dominant_topic
      by_topic = @school.dig("sentiment_stats", "sentiment_by_topic")
      return nil unless by_topic.is_a?(Hash)

      best = by_topic
             .reject { |topic, _| topic == "Other" }
             .map { |topic, counts| [topic, counts["total"].to_i, counts] }
             .select { |_, total, _| total.positive? }
             .max_by { |_, total, _| total }
      return nil unless best

      topic, _total, counts = best
      pos = counts["positive"].to_i
      neg = counts["negative"].to_i
      mood = pos > neg ? "mostly positive" : (neg > pos ? "mostly negative" : "mixed")
      "#{topic}: #{mood}"
    end

    def level_name(code)
      { "p" => "preschool", "e" => "elementary", "m" => "middle", "h" => "high" }.fetch(code, code)
    end

    def finding(status, evidence, as_of)
      raise ArgumentError, "bad status #{status}" unless STATUSES.include?(status)

      { "status" => status, "evidence" => evidence, "as_of" => as_of }
    end

    def stringify(hash)
      hash.transform_keys(&:to_s)
    end
  end
end
