module Api
  class ShortlistController < BaseController
    before_action :validate_school_id

    def create
      search_session = current_search_session
      entries = search_session.shortlist_entries
      entry = entries.find_by(school_id: params[:school_id])
      return respond_with_school(entry) if entry

      school = search_session.matching_results.find { |result| (result["id"] || result["school_id"]).to_s == params[:school_id] }
      unless school
        return render_error("school_not_in_results", :not_found, "That school is no longer in your search results.")
      end

      entry = entries.create_or_find_by!(school_id: params[:school_id]) { |record| record.school = school }
      respond_with_school(entry, status: entry.previously_new_record? ? :created : :ok)
    end

    def destroy
      current_search_session.shortlist_entries.where(school_id: params[:school_id]).delete_all
      if request.format.html?
        redirect_to guided_search_path, status: :see_other
      else
        head :no_content
      end
    end

    private

    def respond_with_school(entry, status: :ok)
      if request.format.html?
        redirect_to guided_search_path, status: :see_other
      else
        render json: { school: entry.school }, status: status
      end
    end

    def validate_school_id
      id = params[:school_id]
      return if id.is_a?(String) && ShortlistEntry::SCHOOL_ID.match?(id)

      render_error("invalid_school_id", :unprocessable_content, "That school has an invalid ID.")
    end
  end
end
