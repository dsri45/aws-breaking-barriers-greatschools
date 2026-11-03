
module GuidedSearch
  class BedrockAgent
    def initialize(extractor: NeedsExtractor.new)
      @extractor = extractor
    end

    def call(message:, history:, preferences:)
      extracted = @extractor.extract(
        message: message,
        history: history,
        preferences: preferences
      )

      questions = [extracted["clarifying_question"]].compact

      has_location = extracted["location"].present?
      has_grade = extracted["grade_level"].present?
      has_needs = extracted["needs"].any?

      # If the parent has provided location and grade but
      # doesn't know their priorities, guide discovery.
      if has_location && has_grade && !has_needs
        questions = [
          "What matters most to your family: academics, " \
          "school culture, student support, or extracurricular activities?"
        ]
      end

      # Only search once we have location, grade, and
      # at least one school preference.
      ready_to_search = has_location && has_grade && has_needs

      {
        preferences: extracted,
        follow_up_questions: questions,
        search: ready_to_search
      }
    end

    def reply(guidance:, results:)
      questions = guidance.fetch(:follow_up_questions)

      if guidance[:search]
        message = "Retrieved #{results.size} synthetic demo results for testing."
      elsif guidance.dig(:preferences, "needs").empty?
        message = "Let's explore what matters most to your family."
      else
        message = "Let's narrow down your school search."
      end

      ([message] + questions).join(" ")
    end
  end
end
