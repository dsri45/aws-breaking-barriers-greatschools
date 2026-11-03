module Api
  class SearchesController < BaseController
    rate_limit to: 15, within: 1.minute, only: :create,
      with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }

    rescue_from ActiveRecord::StaleObjectError do
      render json: { error: "session_changed" }, status: :conflict
    end

    rescue_from GuidedSearch::UpstreamError do |error|
      Rails.logger.warn("Guided search dependency failed (#{error.message})")
      render json: { error: "search_unavailable" }, status: :service_unavailable
    end

    def create
      message = params[:message]
      unless message.is_a?(String) && message.strip.present? && message.length <= 2000
        return render json: { error: "message_must_be_1_to_2000_characters" }, status: :unprocessable_content
      end

      render json: GuidedSearch::Turn.new(current_search_session).call(message.strip)
    end
  end
end
