module Api
  class BaseController < ApplicationController
    protect_from_forgery with: :exception
    before_action :require_json, only: :create
    before_action :disable_caching

    rescue_from ActionController::InvalidAuthenticityToken do
      render json: { error: "invalid_csrf_token" }, status: :unprocessable_content
    end

    private

    def require_json
      return if request.media_type == "application/json"

      render json: { error: "expected_json" }, status: :unsupported_media_type
    end

    def disable_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def current_search_session
      @current_search_session ||= SearchSession.find_by(id: session[:guided_search_id]) ||
        SearchSession.create!.tap { |search_session| session[:guided_search_id] = search_session.id }
    end
  end
end
