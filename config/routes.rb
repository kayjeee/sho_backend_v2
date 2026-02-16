# frozen_string_literal: true

Rails.application.routes.draw do

  # =========================================================
  # HEALTH CHECK (VERY IMPORTANT FOR RAILWAY)
  # =========================================================
  root to: proc { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
  get "/health", to: proc { [200, { "Content-Type" => "text/plain" }, ["OK"]] }

  # =========================================================
  # API V1
  # =========================================================
  namespace :api do
    namespace :v1 do

      # ---------------- ADMIN USERS ----------------
      namespace :admin_users do
        get :schools_for_admin
      end

      # ---------------- USERS (Auth0 SAFE) ----------------
      scope :users, controller: :users do
        get   :show
        get   :schools
        get   :me
        put   :update_roles
        post  :add_school
        get   :onboarding_status
        patch :update_profile
      end

      # ---------------- USERS (Backward Compatibility) ----------------
      get "users/:auth0_id", to: "users#show_by_path", constraints: { auth0_id: /[^\/]+/ }
      get "users/:auth0_id/schools", to: "users#schools_by_path", constraints: { auth0_id: /[^\/]+/ }
      get "users/:auth0_id/onboarding_status", to: "users#onboarding_status_by_path", constraints: { auth0_id: /[^\/]+/ }

      # ---------------- USERS INTERNAL ----------------
      resources :users, only: [:create] do
        member do
          get  :roles
          post :add_role
          get  :onboarding_required

          resource :onboarding_status, controller: :onboarding_statuses, only: [:show, :update] do
            post :complete_step
            post :skip_step
            post :reset
          end
        end
      end

      # ---------------- PARENTS ----------------
      scope :parents, controller: :my_learners do
        get :my_learners, action: :index
        get :profile
      end

      resources :learner_links, only: [:create]

      # ---------------- INVITES ----------------
      resources :invites, only: [:create, :show, :update] do
        member do
          post :generate_pr_code
          post :create_short_link
        end
      end

      resources :invitations, param: :token, only: [:create] do
        collection do
          post :verify
          post :bulk_create
        end
      end

      resources :learner_invitations do
        member do
          post :accept
          post :decline
          post :cancel
          post :resend
        end
        collection do
          get :pending
          get :expired
          get "by_grade/:grade_id", action: :by_grade
        end
      end

      resources :teacher_invitations do
        member do
          post :accept
          post :decline
          post :cancel
          post :resend
        end
        collection do
          get :pending
          get :expired
          get "by_school/:school_id", action: :by_school
        end
      end

      # ---------------- SCHOOLS ----------------
      resources :schools do
        member do
          get :admins
          get :teachers
          get :parents
          get "parents/:parent_id", to: "schools#show_parent"
        end

        collection { get :search }

        resources :students
        resources :grades, only: [:index, :create]
        resources :learners, only: [:index]
        resources :pr_codes
        resources :transactions do
          collection do
            get :pending
            get :completed
          end
        end
      end

      # ---------------- GRADES ----------------
      resources :grades do
        member do
          get :learners
          get :teachers
          get :stats
          post :invite_learner
          post :invite_teacher
        end
      end

      # ---------------- ACADEMIC ----------------
      resources :learners
      resources :subjects
      resources :assessments
      resources :results

      # ---------------- SYSTEM ----------------
      resources :transactions do
        member { post :process_payment }
      end

      resources :conversations do
        resources :messages
      end

      resources :uploads
      resources :notifications do
        collection do
          patch :mark_all_read
          get :unread_count
        end
      end

      # ---------------- AUTH ----------------
      scope :auth, controller: :authentication do
        post :login
        post :logout
        post :refresh
        post :forgot_password
        post :reset_password
      end

      # ---------------- PUBLIC INVITES ----------------
      namespace :public do
        namespace :invitations do
          post "learner/:token/accept", action: :accept_learner_invitation
          post "teacher/:token/accept", action: :accept_teacher_invitation
          get  "learner/:token", action: :show_learner_invitation
          get  "teacher/:token", action: :show_teacher_invitation
        end
      end

    end
  end

  # =========================================================
  # GLOBAL ROUTES
  # =========================================================
  get "api/docs", to: "api/v1/documentation#index"
  get "invitations/:token/verify_with_details", to: "api/v1/invitations#verify_with_details"

end
