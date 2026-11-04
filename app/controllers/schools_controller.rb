class SchoolsController < ApplicationController
  before_action :load_schools

  def show
    @school = @available_schools.find { |school| school.school_id == params[:school_id] }
    return head :not_found unless @school

    @profile = SchoolProfile.for(@school)
    @related_schools = @available_schools.reject { |school| school.school_id == @school.school_id }
  end

  def compare
    ids = Array(params[:ids])
    @schools = @available_schools.select { |school| ids.include?(school.school_id) }
    if @schools.size < 2
      redirect_to @back_path, alert: "Select at least two schools to compare."
    end
  end

  private

  def load_schools
    search_session = stored_search_session
    @allow_saving = search_session&.history.present?
    shortlist = search_session ? search_session.shortlist_entries.order(:id).to_a : []
    show_shortlist = params[:view] == "shortlist"
    @back_path = show_shortlist ? root_path(view: "shortlist") : root_path
    @available_schools = if !show_shortlist && search_session&.history.blank?
      SearchResult.sample.schools
    else
      SearchResult.from_session(search_session, shortlist: shortlist, show_shortlist: show_shortlist).schools
    end
  end
end
