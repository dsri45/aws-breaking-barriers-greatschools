class ApplicationController < ActionController::Base
  private

  def stored_search_session
    SearchSession.find_by(id: session[:guided_search_id]) if session[:guided_search_id]
  end
end
