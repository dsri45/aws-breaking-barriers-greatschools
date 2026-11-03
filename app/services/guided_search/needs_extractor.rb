
module GuidedSearch
  class NeedsExtractor
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
      prompt = <<~PROMPT
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

        JSON keys:
        needs, location, grade_level,
        missing_information, clarifying_question

        Parent message and previous context:
        #{JSON.generate({
          message: message,
          history: history,
          preferences: preferences
        })}
      PROMPT

      response = @bedrock.converse(
        messages: [
          {
            role: "user",
            content: [{ text: prompt }]
          }
        ],
        inference_config: {
          max_tokens: 700,
          temperature: 0.1
        }
      )

      text = response.output.message.content
        .filter_map(&:text)
        .join("\n")
        .strip

      # Handle optional Markdown JSON fences.
      text = text.sub(/\A```(?:json)?\s*/i, "")
                 .sub(/\s*```\z/, "")

      result = JSON.parse(text)

      unless result.is_a?(Hash) && result["needs"].is_a?(Array)
        raise ArgumentError, "Invalid needs extraction response"
      end

      unknown = result["needs"] - NEEDS
      unless unknown.empty?
        raise ArgumentError, "Unknown needs: #{unknown.join(', ')}"
      end

      result["missing_information"] ||= []
      result
    end
  end
end
