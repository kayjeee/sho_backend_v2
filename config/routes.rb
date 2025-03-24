Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # User Routes
      resources :users, only: [:index, :show, :create, :update] do
        member do
          get :roles
          post :add_role
          patch :update_roles
          get :schools
        end
      end

      # School Routes
      resources :schools, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :admin_access
          patch :update_roles
        end
        collection do
          get :search
        end
      end

      # Request Access Routes
      resources :request_accesses do
        collection do
          get 'school/:school_id', action: :by_school
          get :pending_requests # Keep for backward compatibility
          get :approved_schools # Keep for backward compatibility
        end
      end

      # Fetch all requests for a specific school
      get 'request_accesses/school/:school_id', to: 'request_accesses#by_school'

      # Conversation Routes
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:create, :index]
      end
    end
  end
end