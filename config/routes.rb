Rails.application.routes.draw do
  get 'fields/index'
  resources :fields do
    collection { post :import }
  end
  resource :search, only: :show, controller: :search

  root :to => 'search#show'

  get "/pages/:page" => "pages#show"
  
end
