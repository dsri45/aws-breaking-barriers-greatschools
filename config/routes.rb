Rails.application.routes.draw do
  root "home#show"
  get "up" => "rails/health#show"
  get "ready" => "health#ready"
  post "search-options" => "search_options#update", as: :search_options
  get "schools/compare" => "schools#compare", as: :compare_schools
  get "schools/:school_id" => "schools#show", as: :school_profile

  namespace :api, defaults: { format: :json } do
    resource :search_session, path: "session", only: :show
    post "search" => "searches#create"
    resources :shortlist, only: %i[create destroy], param: :school_id
  end
end
