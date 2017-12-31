Rails.application.routes.draw do
  get 'fields/index'

  root :to => 'fields#index'

  resources :fields do
    collection { post :import }
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
