class ChatSessionsController < ApplicationController
  PAGE_SIZE = 20

  protect_from_forgery with: :exception
  before_action :require_html
  before_action :disable_caching

  def index
    @active_chat = stored_search_session
    chats = browser_search_sessions.with_history
    @total_pages = [chats.count.fdiv(PAGE_SIZE).ceil, 1].max
    @page = [[params[:page].to_s.to_i, 1].max, @total_pages].min
    @chats = chats.select(:id, :history, :preferences, :updated_at)
      .order(updated_at: :desc, id: :desc).offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
  end

  def create
    previous = stored_search_session
    chat = previous if previous && previous.history.empty?
    chat ||= browser_search_sessions.create!
    activate_search_session(chat)
    redirect_to chat_path(chat.id), status: :see_other
  end

  private

  def require_html
    head :not_acceptable unless request.format.html?
  end

  def disable_caching
    response.headers["Cache-Control"] = "no-store"
  end
end
