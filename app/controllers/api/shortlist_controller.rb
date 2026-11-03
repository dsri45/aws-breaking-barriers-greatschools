module Api
  class ShortlistController < BaseController
    before_action :validate_school_id

    def create
      search_session = current_search_session
      entries = search_session.shortlist_entries
      entry = entries.find_by(school_id: params[:school_id])
      return render json: { school: entry.school } if entry

      school = search_session.results.find { |result| result.fetch("id") == params[:school_id] }
      return render json: { error: "school_not_in_results" }, status: :not_found unless school

      entry = entries.create_or_find_by!(school_id: params[:school_id]) { |record| record.school = school }
      render json: { school: entry.school }, status: entry.previously_new_record? ? :created : :ok
    end

    def destroy
      current_search_session.shortlist_entries.where(school_id: params[:school_id]).delete_all
      head :no_content
    end

    private

    def validate_school_id
      id = params[:school_id]
      return if id.is_a?(String) && ShortlistEntry::SCHOOL_ID.match?(id)

      render json: { error: "invalid_school_id" }, status: :unprocessable_content
    end
  end
end
