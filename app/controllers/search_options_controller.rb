class SearchOptionsController < ApplicationController
  GRADES = { "p" => "Preschool", "e" => "K–5", "m" => "6–8", "h" => "9–12" }.freeze

  rate_limit to: 30, within: 1.minute,
    with: -> { redirect_to root_path, alert: "Too many changes. Try again in a minute.", status: :see_other }

  rescue_from ActiveRecord::StaleObjectError do
    redirect_to root_path, alert: "Your conversation changed in another tab. Please try again.", status: :see_other
  end

  rescue_from GuidedSearch::UpstreamError do |error|
    Rails.logger.warn("Guided search dependency failed (#{error.message})")
    redirect_to root_path, alert: "Search is temporarily unavailable. Please try again.", status: :see_other
  end

  def update
    search_session = stored_search_session
    return redirect_to root_path, status: :see_other if search_session&.history.blank?

    preferences = search_session.preferences.deep_dup
    case params[:change]
    when "refresh"
      GuidedSearch::Turn.new(search_session).refresh(preferences) if search_session.follow_up_questions.empty?
    when "toggle", "add", "grade", "remove"
      return redirect_to root_path, status: :see_other unless update_priority(preferences)

      if search_session.follow_up_questions.empty?
        GuidedSearch::Turn.new(search_session).refresh(preferences)
      else
        search_session.update!(preferences: preferences)
      end
    when "feedback"
      if params[:answer].in?(%w[yes no])
        search_session.update!(preferences: preferences.merge("priority_feedback" => params[:answer]))
      end
    end
    redirect_to root_path, status: :see_other
  end

  private

  def update_priority(preferences)
    criteria = preferences["criteria"] ||= []
    if params[:change] == "grade"
      code = params[:grade].to_s
      return false unless code.empty? || GRADES.key?(code)

      filters = preferences["filters"] ||= {}
      criteria.reject! { |criterion| criterion["key"] == "level" }
      if code.empty?
        filters.delete("level_codes")
        preferences["grade_level"] = GuidedSearch::NeedsExtractor::ANY_GRADE
      else
        filters["level_codes"] = code
        preferences["grade_level"] = GRADES.fetch(code)
        criteria.unshift("key" => "level", "label" => GRADES.fetch(code), "importance" => "require")
      end
      preferences["query"] = [Array(preferences["needs"]).join(", "), preferences["grade_level"],
        preferences["location"]].compact_blank.join(" · ")
    elsif params[:change] == "remove"
      key = params[:key]
      return false if key.in?(%w[level location])

      criterion = criteria.find { |existing| existing["key"] == key }
      return false unless criterion

      criteria.delete(criterion)
      preferences["needs"] = Array(preferences["needs"]) - [criterion["label"]]
      preferences["priority_overrides"]&.delete(key)
      preferences["query"] = [Array(preferences["needs"]).join(", "), preferences["grade_level"],
        preferences["location"]].compact_blank.join(" · ")
    elsif params[:change] == "add"
      need = params[:need]
      return false unless GuidedSearch::NeedsExtractor::NEEDS.include?(need)

      criterion = GuidedSearch::BedrockAgent.criterion_for(need)
      return false if criteria.any? { |existing| existing["key"] == criterion["key"] }

      criterion["importance"] = "require"
      criteria << criterion
      preferences["needs"] = Array(preferences["needs"]) | [need]
      (preferences["priority_overrides"] ||= {})[criterion["key"]] = "require"
      preferences["query"] = [preferences["query"], need].compact_blank.join(" · ")
    else
      key = params[:key]
      return false if key.in?(%w[level location])

      criterion = criteria.find { |existing| existing["key"] == key }
      return false unless criterion

      importance = criterion["importance"] == "require" ? "prefer" : "require"
      criterion["importance"] = importance
      (preferences["priority_overrides"] ||= {})[key] = importance
    end
    true
  end
end
