class ApplicationController < ActionController::Base
  def default_url_options
    super.merge(chat_id: @stored_search_session&.id).compact
  end

  private

  def stored_search_session
    return @stored_search_session if defined?(@stored_search_session)

    requested_id = params[:chat_id].presence
    if requested_id && !requested_id.to_s.match?(/\A[1-9]\d*\z/)
      raise ActiveRecord::RecordNotFound
    end
    id = requested_id || session[:guided_search_id]
    return @stored_search_session = nil unless id

    search_session = SearchSession.find_by(id: id)
    if search_session && search_session.browser_token_digest.nil? && search_session.id == session[:guided_search_id].to_i
      # An existing encrypted session cookie can claim its legacy conversation.
      SearchSession.where(id: search_session.id, browser_token_digest: nil)
        .update_all(browser_token_digest: browser_token_digest)
      search_session.reload
    end
    unless search_session&.browser_token_digest == browser_token_digest
      raise ActiveRecord::RecordNotFound if requested_id

      return @stored_search_session = nil
    end
    activate_search_session(search_session)
  end

  def browser_search_sessions
    SearchSession.where(browser_token_digest: browser_token_digest)
  end

  def browser_token_digest
    return @browser_token_digest if @browser_token_digest

    token = cookies.encrypted[:guided_search_browser]
    unless token.present?
      legacy_id = session[:guided_search_id]
      token = if legacy_id
        OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "guided-browser/#{legacy_id}")
      else
        SecureRandom.hex(32)
      end
    end
    cookies.encrypted[:guided_search_browser] = {
      value: token, expires: 30.days.from_now, httponly: true,
      secure: Rails.env.production?, same_site: :lax
    }
    @browser_token_digest = Digest::SHA256.hexdigest(token)
  end

  def activate_search_session(search_session)
    session[:guided_search_id] = search_session.id
    @stored_search_session = search_session
    @current_search_session = search_session
  end

  def search_return_path(view: nil)
    if params[:chat_id].present?
      chat_path(stored_search_session.id, view: view)
    else
      root_path(view: view)
    end
  end
end
