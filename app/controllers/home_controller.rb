class HomeController < ApplicationController
  def show
    search_session = stored_search_session
    shortlist = search_session ? search_session.shortlist_entries.order(:id).to_a : []
    @show_shortlist = params[:view] == "shortlist"
    @shortlist_count = shortlist.size
    @show_preview = !@show_shortlist && search_session&.history.blank?
    @editable_priorities = !@show_shortlist && !@show_preview
    @can_refresh = @editable_priorities && search_session.follow_up_questions.empty?
    @priority_feedback = search_session&.preferences&.fetch("priority_feedback", nil)
    @search = if @show_preview
      SearchResult.sample
    else
      SearchResult.from_session(search_session, shortlist:, show_shortlist: @show_shortlist)
    end
  end
end
