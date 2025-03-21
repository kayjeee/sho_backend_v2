Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # User routes
      resources :users, only: [:index, :show, :create] do
        member do
          get :roles  # For fetching user roles
          post :add_role # For adding a role (e.g., admin)
          patch :update_roles  # For updating a user's roles
          get :schools    # Route to fetch schools associated with a specific userget :schools # Route to fetch schools associated with a specific user
        end
      end

      # School routes
      resources :schools, only: [:index, :show, :create,:destroy,:update] do
        member do
          get :admin_access # Check if a user has admin access to the school
          patch :update_roles # Update roles for a school user
        end
      
        collection do
          get :search # Custom route for searching schools
        end
      end

      # Public and private endpoints
      get 'public' => 'public#public'
      get 'private' => 'private#private'
      get 'private-scoped' => 'private#private_scoped'
    end
  end

  # Health check endpoint
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
