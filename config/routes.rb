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
          get :admins
          get :teachers
          get :parents
          
          # Student Management Routes
          resources :students, only: [:index, :show, :create, :update, :destroy]
          
          # Transaction Routes
          resources :transactions, only: [:index, :create] do
            collection do
              get :pending
              get :completed
            end
          end
        end
        
        collection do
          get :search
        end
      end

      # Transaction Routes (global)
      resources :transactions, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :process_payment
        end
      end

      # Request Access Routes
      resources :request_accesses, only: [:index, :show, :create, :update, :destroy] do
        get 'users_by_roles', to: 'schools#users_by_roles'
        collection do
          get 'school/:school_id', action: :by_school
          get :pending_requests
          get :approved_schools
          post :approve
          post :reject
        end
      end

      # Conversation Routes
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:create, :index]
      end
    end
  end
end