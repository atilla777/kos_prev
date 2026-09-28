Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "readiness#show", as: :readiness
  get "status", to: "statuses#show", as: :coordination_status

  resources :projects, only: %i[index create show update]
  get "workflows/schema", to: "workflows#schema", as: :workflow_schema
  resources :workflows, only: %i[index create show]
  get "projects/:project_id/plans", to: "task_plans#index", as: :project_plans
  put "projects/:project_id/plan", to: "task_plans#update", as: :project_plan
  get "projects/:project_id/plan", to: "task_plans#show"
  post "projects/:project_id/plan/abandon", to: "task_plans#abandon", as: :abandon_project_plan
  get "projects/:project_id/tasks", to: "tasks#index", as: :project_tasks

  get "tasks/ready", to: "tasks#ready"
  resources :tasks, only: :show do
    member do
      get :context
      get :result
      post :claim
      post :takeover
      post :release
      post :report
      post :answer
    end
  end
end
