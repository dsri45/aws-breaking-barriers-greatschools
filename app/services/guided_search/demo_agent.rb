module GuidedSearch
  class DemoAgent
    def call(message:, history:, preferences:)
      {
        preferences: preferences.merge("query" => message),
        follow_up_questions: history.empty? ? ["Which grade and ZIP code should we use?"] : [],
        search: true
      }
    end

    def reply(guidance:, results:)
      "Demo search returned #{results.size} synthetic school. #{guidance.fetch(:follow_up_questions).join(" ")}".strip
    end
  end
end
