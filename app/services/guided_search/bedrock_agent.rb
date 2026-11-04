module GuidedSearch
  class BedrockAgent
    EVIDENCE_KEYS = {
      "AP offered" => "ap",
      "Arts programs" => "arts",
      "Career preparation" => "career_prep",
      "Gifted and Talented program" => "gifted_talented",
      "Highly rated" => "rating",
      "IB offered" => "ib",
      "Positive reviews" => "reviews",
      "Reading club" => "reading_club",
      "Small class sizes" => "class_size",
      "Sports programs" => "sports_programs",
      "Transportation options" => "transportation"
    }.freeze

    def self.criterion_for(need)
      { "key" => EVIDENCE_KEYS.fetch(need) { need.parameterize(separator: "_") },
        "label" => need, "importance" => "require" }
    end

    def initialize(extractor: NeedsExtractor.new)
      @extractor = extractor
    end

    def call(message:, history:, preferences:)
      extracted = @extractor.extract(message:, history:, preferences:)
      needs = extracted.fetch("needs")
      criteria = needs.map { |need| self.class.criterion_for(need) }
      if extracted.dig("filters", "level_codes")
        criteria.unshift({ "key" => "level", "label" => extracted["grade_level"], "importance" => "require" })
      end

      has_location = extracted["location"].present?
      has_grade = extracted["grade_level"].present?
      ready_to_search = has_location && has_grade && needs.any?
      question = if has_location && has_grade && needs.empty?
        "What matters most to your family: academics, school culture, student support, or extracurricular activities?"
      elsif !ready_to_search
        extracted["clarifying_question"] || (has_location ? "What grade level are you looking for?" : "What city and state or ZIP code should I search?")
      end

      {
        preferences: extracted.merge("query" => extracted["query"].presence || message, "criteria" => criteria),
        follow_up_questions: Array(question),
        search: ready_to_search
      }
    end

    def reply(guidance:, results:)
      if guidance.fetch(:search)
        SchoolGuide.recommendations(preferences: guidance.fetch(:preferences), results: results)
      else
        "Happy to help. Let's build this around your learner. #{guidance.fetch(:follow_up_questions).first}"
      end
    end
  end
end
