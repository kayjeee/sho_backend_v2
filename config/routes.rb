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
          get 'parents/:parent_id', to: 'schools#show_parent'
          
          # Student Management Routes
          resources :students, only: [:index, :show, :create, :update, :destroy]
          
          # Transaction Routes
          resources :transactions, only: [:index, :create] do
            collection do
              get :pending
              get :completed
            end
          end

          # Debt Management Routes (NEW)
          get 'debt_summary', to: 'debt_management#summary'
          get 'debtors', to: 'debt_management#index'
          get 'accounts/:account_id', to: 'debt_management#show_account'
          get 'accounts/:account_id/payments', to: 'debt_management#account_payments'
          post 'accounts/:account_id/payments', to: 'debt_management#create_payment'
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