module GuidedSearch
  class Turn
    MAX_HISTORY = 20

    def initialize(search_session)
      @search_session = search_session
    end

    def call(message)
      agent = ENV.fetch("GUIDED_SEARCH_AGENT", "GuidedSearch::DemoAgent").constantize.new
      search = ENV.fetch("GUIDED_SEARCH_RETRIEVER", "GuidedSearch::DemoSearch").constantize.new

      guidance = agent.call(
        message: message,
        history: @search_session.history.deep_dup,
        preferences: @search_session.preferences.deep_dup
      )
      preferences = guidance.fetch(:preferences)
      questions = guidance.fetch(:follow_up_questions)
      results = guidance.fetch(:search) ? search.call(preferences: preferences).as_json : []
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
  end
end
