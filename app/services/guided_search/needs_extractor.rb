module GuidedSearch
  class NeedsExtractor
    ANY_GRADE = "Any grade"
    ANY_GRADE_REPLY = /\A(?:any|all) grades?(?: levels?)?(?: (?:is|are) fine)?[.!]?\z/i
    NO_PREFERENCE_REPLY = /\A(?:any|anything|no preference|(?:it )?doesn['’]t matter)[.!]?\z/i

    NEEDS = [
      "Advanced coursework access",
      "After-school care",
      "After-school clubs",
      "Alternative pedagogy",
      "AP offered",
      "Arts programs",
      "Balanced performance",
      "Career preparation",
      "College counseling",
      "College readiness",
      "Diverse student body",
      "Early learning foundation",
      "Faith-based school",
      "Financial aid available",
      "Gifted and Talented program",
      "High attendance",
      "High test scores",
      "High-quality, supportive teachers",
      "Highly rated",
      "IB offered",
      "IEP and 504 support",
      "Inclusive climate",
      "Language programs",
      "Learning differences support",
      "Low academic pressure",
      "Low exclusionary discipline",
      "Mental health support",
      "Microschool",
      "Positive culture",
      "Positive reviews",
      "Reasonable homework load",
      "Resources and supports",
      "Safe environment",
      "Schedule compatibility",
      "Short commute",
      "Small class sizes",
      "Small school",
      "Sports programs",
      "STEM programs",
      "Strong academics",
      "Strong core math",
      "Strong growth",
      "Strong leadership",
      "Strong reading and writing",
      "Support for students learning English",
      "Transportation options"
    ].freeze

    def initialize(bedrock: Bedrock.new)
      @bedrock = bedrock
    end

    def extract(message:, history: [], preferences: {})
      if preferences["needs"].is_a?(Array) && any_grade_reply?(message, history)
        return preferences.except("missing_information").merge(
          "grade_level" => ANY_GRADE,
          "filters" => filters_for(preferences["filters"], preferences["location"], ANY_GRADE),
          "query" => preferences["query"].presence || [*preferences["needs"], preferences["location"]].compact.join(" "),
          "clarifying_question" => nil
        )
      end

      instructions = <<~PROMPT
        You are the needs extractor for Atlas, a GreatSchools
        guided school discovery agent.

        Identify the parent's school preferences using ONLY
        these official GreatSchools needs:

        #{NEEDS.join(", ")}

        Rules:
        - Use exact need names from the list.
        - Do not invent preferences.
        - Preserve previously confirmed preferences unless
          the parent explicitly changes them.
        - Extract location and grade level separately.
        - When no needs are stated, return an empty array.
        - Identify important missing information.
        - Ask exactly one useful clarifying question, or null
          if no question is needed.
        - Return valid JSON only.

        JSON fields:
        - needs: array of exact need names.
        - location: the stated city and state, or ZIP code, as a string. Use null
          for an ambiguous location such as "near me". Do not invent a location.
        - grade_level: the stated grade or school level as a string, or null.
          Use "#{ANY_GRADE}" when the parent is open to all grades, including
          "any" or "no preference" in reply to a grade question. Keep this
          preference on later turns unless the parent asks for a specific grade.
        - query: short school search query carrying forward the current location,
          needs, grade level, and any school name the parent gave. A short answer
          to a follow-up should refine the existing query.
        - filters: object with optional state (two-letter US abbreviation), city
          (city name only), zipcode (five digits as a string), and level_codes
          (one of p for preschool, e for K–5, m for 6–8, h for 9–12).
          A bare five-digit ZIP is an exact filter. If the parent explicitly
          asks for schools near a ZIP, keep "near" in the location description.
          Omit level_codes for "#{ANY_GRADE}" and any filter you cannot infer.
        - missing_information: array of missing details.
        - clarifying_question: one question to get the location, grade, or a need.
          Use null when all three are known.
      PROMPT

      context = JSON.generate({ message: message, history: history, preferences: preferences })
      response = @bedrock.converse(
        system: [{ text: instructions }],
        messages: [{ role: "user", content: [{ text: context }] }],
        inference_config: {
          max_tokens: 700,
          temperature: 0.1
        }
      )

      text = Array(response.output&.message&.content)
        .filter_map(&:text)
        .join("\n")
        .strip

      # Handle optional Markdown JSON fences.
      text = text.sub(/\A```(?:json)?\s*/i, "")
                 .sub(/\s*```\z/, "")

      result = JSON.parse(text)

      unless result.is_a?(Hash) && result["needs"].is_a?(Array) && (result["needs"] - NEEDS).empty?
        raise UpstreamError, "Bedrock returned invalid school preferences"
      end

      result["needs"] = result["needs"].uniq
      %w[location grade_level query clarifying_question].each do |key|
        value = result[key]
        value = "Grade #{value}" if key == "grade_level" && value.is_a?(Integer)
        result[key] = value.is_a?(String) ? value.strip.presence : nil
      end
      grade_level = result["grade_level"] || preferences["grade_level"].presence_in([ANY_GRADE])
      result["grade_level"] = ANY_GRADE_REPLY.match?(grade_level.to_s) ? ANY_GRADE : grade_level
      result["filters"] = filters_for(result["filters"], result["location"], result["grade_level"])
      result["missing_information"] = Array(result["missing_information"]).grep(String)
      result.slice("needs", "location", "grade_level", "query", "filters", "missing_information", "clarifying_question")
    rescue JSON::ParserError
      raise UpstreamError, "Bedrock returned invalid school preferences"
    end

    private

    def any_grade_reply?(message, history)
      answer = message.strip
      return true if ANY_GRADE_REPLY.match?(answer)

      last_turn = history.last
      NO_PREFERENCE_REPLY.match?(answer) && last_turn&.fetch("role", nil) == "assistant" &&
        last_turn["content"].to_s.match?(/\b(?:grade|school) level\b|\b(?:what|which) grade\b/i)
    end

    def filters_for(filters, location, grade_level)
      filters = normalize_filters(filters)
      zipcode = location&.match(/\A(?:ZIP(?: code)?\s+)?([0-9]{5})\z/i)
      filters["zipcode"] = zipcode[1] if zipcode
      filters.delete("level_codes") if grade_level&.casecmp?(ANY_GRADE)
      filters
    end

    def normalize_filters(filters)
      return {} unless filters.is_a?(Hash)

      state, city, zipcode, level = filters.values_at("state", "city", "zipcode", "level_codes").map do |value|
        value.strip if value.is_a?(String)
      end
      {
        "state" => (state.upcase if state&.match?(/\A[a-z]{2}\z/i)),
        "city" => city&.downcase&.presence,
        "zipcode" => (zipcode if zipcode&.match?(/\A[0-9]{5}\z/)),
        "level_codes" => level.presence_in(%w[p e m h])
      }.compact
    end
  end
end
