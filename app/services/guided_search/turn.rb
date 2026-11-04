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

      @search_session.update!(
        history: updated_history(message, reply, schools: results.first(3)),
        preferences: preferences,
        results: results,
        follow_up_questions: questions
      )

      { reply: reply, preferences: preferences, follow_up_questions: questions, results: results }
    end

    def refresh(preferences)
      results = retrieve(preferences)
      reply = SchoolGuide.recommendations(preferences: preferences, results: results)
      history = @search_session.history + [{
        "role" => "assistant", "content" => "I've updated the shortlist using your priorities.\n\n#{reply}",
        "school_ids" => results.first(3).map { |school| (school["id"] || school["school_id"]).to_s }
      }]
      @search_session.update!(preferences: preferences, results: results, history: history.last(MAX_HISTORY))
    end

    def detail(message:, intent:, school_id: nil, shortlist: false)
      results = @search_session.matching_results
      if intent == "explain_results"
        schools = shortlist ? @search_session.shortlist_entries.order(:id).map(&:school) : results
        preferences = shortlist ? {} : @search_session.preferences
        reply = SchoolGuide.recommendations(preferences: preferences, results: schools)
      else
        school = results.find { |result| (result["id"] || result["school_id"]).to_s == school_id } ||
          @search_session.shortlist_entries.find_by(school_id: school_id)&.school
        return unless school

        guide = SchoolGuide.new(school)
        schools = [school]
        reply = intent == "visit_questions" ? guide.visit_reply : guide.explanation
      end
      @search_session.update!(history: updated_history(message, reply, schools: schools.first(3)))
      { reply: reply, preferences: @search_session.preferences, follow_up_questions: @search_session.follow_up_questions, results: results }
    end

    private

    def updated_history(message, reply, schools:)
      (@search_session.history + [
        { "role" => "user", "content" => message },
        { "role" => "assistant", "content" => reply,
          "school_ids" => schools.map { |school| (school["id"] || school["school_id"]).to_s } }
      ]).last(MAX_HISTORY)
    end

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
      results.select! do |result|
        EvidenceScorer.matches?(criteria: preferences["criteria"], evidence: result["criteria"] || result["evidence"])
      end
      results.each { |result| result["id"] ||= result["school_id"].to_s if result["school_id"].present? }
      results.each { |result| result["why"] ||= SchoolGuide.new(result).short_reason }
      results
    end
  end
end
