module GuidedSearch
  class Turn
    MAX_HISTORY = 20

    def initialize(search_session)
      @search_session = search_session
    end

    def call(message)
      agent = ENV.fetch("GUIDED_SEARCH_AGENT", "GuidedSearch::DemoAgent").constantize.new

      guidance = agent.call(
        message: message,
        history: @search_session.history.deep_dup,
        preferences: @search_session.preferences.deep_dup
      )
      preferences = guidance.fetch(:preferences)
      keep_priority_choices(preferences)
      questions = guidance.fetch(:follow_up_questions)
      results = guidance.fetch(:search) ? retrieve(preferences) : []
      reply = agent.reply(guidance: guidance, results: results)

      history = @search_session.history + [
        { "role" => "user", "content" => message },
        { "role" => "assistant", "content" => reply }
      ]
      @search_session.update!(
        history: history.last(MAX_HISTORY),
        preferences: preferences,
        results: results,
        follow_up_questions: questions
      )

      { reply: reply, preferences: preferences, follow_up_questions: questions, results: results }
    end

    def refresh(preferences)
      results = retrieve(preferences)
      @search_session.update!(preferences: preferences, results: results)
    end

    private

    def keep_priority_choices(preferences)
      overrides = @search_session.preferences["priority_overrides"]
      return if overrides.blank?

      criteria = Array(preferences["criteria"])
      preferences["priority_overrides"] = overrides.slice(*criteria.pluck("key"))
      criteria.each do |criterion|
        importance = overrides[criterion["key"]]
        criterion["importance"] = importance if importance
      end
    end

    def retrieve(preferences)
      retriever = ENV.fetch("GUIDED_SEARCH_RETRIEVER", "GuidedSearch::DemoSearch").constantize.new
      results = retriever.call(preferences: preferences).as_json
      results.each { |result| result["id"] ||= result["school_id"].to_s if result["school_id"].present? }
      results
    end
  end
end
