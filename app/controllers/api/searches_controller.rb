module Api
  class SearchesController < BaseController
    rate_limit to: 15, within: 1.minute, only: :create,
      with: -> { render_error("rate_limited", :too_many_requests, "Too many searches. Try again in a minute.") }

    rescue_from ActiveRecord::StaleObjectError do
      render_error("session_changed", :conflict, "Your conversation changed in another tab. Please try again.")
    end

    rescue_from GuidedSearch::UpstreamError do |error|
      Rails.logger.warn("Guided search dependency failed (#{error.message})")
      render_error("search_unavailable", :service_unavailable, "Search is temporarily unavailable. Please try again.")
    end

    def create
      message = params[:message]
      unless message.is_a?(String) && message.strip.present? && message.length <= 2000
        return render_error("message_must_be_1_to_2000_characters", :unprocessable_content,
          "Enter a message between 1 and 2,000 characters.")
      end

      intent = params[:intent].presence
      unless intent.nil? || intent.in?(%w[explain_results explain_school visit_questions])
        return render_error("invalid_intent", :unprocessable_content, "Choose a school guide action.")
      end
      if intent.in?(%w[explain_school visit_questions]) && !params[:school_id].is_a?(String)
        return render_error("invalid_school_id", :unprocessable_content, "Choose a school to ask about.")
      end
      service = GuidedSearch::Turn.new(current_search_session)
      turn = if intent
        service.detail(message: message.strip, intent: intent, school_id: params[:school_id], shortlist: params[:view] == "shortlist")
      else
        service.call(message.strip)
      end
      return render_error("school_not_in_results", :not_found, "That school is no longer in your results or saved list.") unless turn
      if request.format.html?
        destination = search_return_path(view: ("shortlist" if intent && params[:view] == "shortlist"))
        redirect_to destination, status: :see_other
      else
        render json: turn
      end
    end
  end
end
