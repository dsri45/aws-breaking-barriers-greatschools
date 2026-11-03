module Api
  class SearchSessionsController < BaseController
    def show
      search_session = current_search_session
      render json: {
        csrf_token: form_authenticity_token,
        history: search_session.history,
        preferences: search_session.preferences,
        results: search_session.results,
        follow_up_questions: search_session.follow_up_questions,
        shortlist: search_session.shortlist_entries.order(:id).map(&:school)
      }
    end
  end
end
