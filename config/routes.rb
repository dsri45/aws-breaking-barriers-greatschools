Rails.application.routes.draw do
  root "home#show"
  get "up" => "rails/health#show"
  get "ready" => "health#ready"

  namespace :api, defaults: { format: :json } do
    resource :search_session, path: "session", only: :show
    post "search" => "searches#create"
    resources :shortlist, only: %i[create destroy], param: :school_id
  end
end
