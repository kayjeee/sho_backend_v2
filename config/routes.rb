# config/routes.rb

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # AdminUser custom route
      get 'admin_users/schools_for_admin', to: 'admin_users#schools_for_admin'

      # User Routes
      resources :users, only: [:index, :show, :create, :update] do
        member do
          get :roles
          post :add_role
          patch :update_roles
          get :schools
          patch :add_school
        end
      end

      # School Routes
      resources :schools, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :admins
          get :teachers
          get :parents
          get 'parents/:parent_id', to: 'schools#show_parent'

          # Debt Management Routes
          get 'debt_summary', to: 'debt_management#summary'
          get 'debtors', to: 'debt_management#index'
          get 'accounts/:account_id', to: 'debt_management#show_account'
          get 'accounts/:account_id/payments', to: 'debt_management#account_payments'
          post 'accounts/:account_id/payments', to: 'debt_management#create_payment'
        end

        collection do
          get :search
        end

        # Nested resources for school-specific operations
        resources :students, only: [:index, :show, :create, :update, :destroy]
        
        resources :transactions, only: [:index, :create] do
          collection do
            get :pending
            get :completed
          end
        end
      end

      # Learner Routes with Bulk Upload
      # Direct route approach
      post 'learners/bulk_upload', to: 'learners#bulk_upload'
      
      # Alternative resources syntax (choose one approach)
      resources :learners, only: [] do
        collection do
          post :bulk_upload
        end
      end

      # Global Transaction Routes
      resources :transactions, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :process_payment
        end
      end

      # Request Access Routes
      resources :request_accesses, only: [:index, :show, :create, :update, :destroy] do
        collection do
          get 'school/:school_id', action: :by_school
          get :pending_requests
          get :approved_schools
          post :approve
          post :reject
        end
        
        member do
          get 'users_by_roles', to: 'schools#users_by_roles'
        end
      end

      # Conversation Routes
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:create, :index]
      end
    end
  end
end