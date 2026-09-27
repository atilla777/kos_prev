Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "readiness#show", as: :readiness

  get "projects", to: "projects#show"
  resources :projects, only: %i[create update]
  resources :workflows, only: :create
  resources :task_types, only: :create
  patch "task_types/:id", to: "task_types#update", as: :task_type

  post "tasks/claim-next", to: "tasks#claim_next"
  post "tasks/create-or-get", to: "tasks#create_or_get"
  post "tasks/create-and-claim", to: "tasks#create_and_claim"
  get "tasks/show-owned", to: "tasks#show_owned"
  get "tasks/resumable", to: "tasks#resumable"
  resources :tasks, only: %i[create show] do
    member do
      get :context
      get :artifact
      post :claim
      post :resume
      post "report-attempt", action: :report_attempt
      post :cancel
      post "materialize-children", action: :materialize_children
      get :children
    end
  end
  patch "tasks/:id", to: "tasks#update"
end
