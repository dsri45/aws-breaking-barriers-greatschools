module Api
  class BaseController < ApplicationController
    protect_from_forgery with: :exception
    before_action :require_supported_body, only: :create
    before_action :disable_caching

    rescue_from ActionController::InvalidAuthenticityToken do
      render_error("invalid_csrf_token", :unprocessable_content, "Please refresh the page and try again.")
    end

    private

    def require_supported_body
      return if request.media_type == "application/json" || (request.format.html? && request.form_data?)

      render_error("expected_json", :unsupported_media_type, "Please use the form to submit your request.")
    end

    def render_error(code, status, message)
      if request.format.html?
        redirect_to guided_search_path, alert: message, status: :see_other
      else
        render json: { error: code }, status: status
      end
    end

    def guided_search_path
      if params[:return_to_profile] == "1" && params[:view] != "shortlist" &&
          params[:school_id].is_a?(String) && ShortlistEntry::SCHOOL_ID.match?(params[:school_id])
        return school_profile_path(params[:school_id])
      end

      params[:view] == "shortlist" ? root_path(view: "shortlist") : root_path
    end

    def disable_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def current_search_session
      @current_search_session ||= stored_search_session ||
        SearchSession.create!.tap { |search_session| session[:guided_search_id] = search_session.id }
    end
  end
end
