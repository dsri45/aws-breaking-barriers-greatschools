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

      turn = GuidedSearch::Turn.new(current_search_session).call(message.strip)
      if request.format.html?
        redirect_to root_path, status: :see_other
      else
        render json: turn
      end
    end
  end
end
