# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do

      # =========================================================
      # ADMIN USERS
      # =========================================================
      namespace :admin_users do
        get :schools_for_admin
      end

      # =========================================================
      # USERS (Auth0-safe — PREFERRED)
      # =========================================================
      # These routes use ?auth0_id=xxx and avoid path parameter collisions
      scope :users, controller: :users do
        get   :show                # ?auth0_id=
        get   :schools             # ?auth0_id=
        get   :me                  # token-based
        put   :update_roles        # ?auth0_id=
        post  :add_school          # ?auth0_id=
        get   :onboarding_status   # ?auth0_id=
        patch :update_profile      # ?auth0_id= (FIXED: Moved to primary scope)
      end

      # =========================================================
      # USERS - Backward Compatibility (DEPRECATED)
      # =========================================================
      # Support old path-based format during migration period
      get 'users/:auth0_id',
          to: 'users#show_by_path',
          constraints: { auth0_id: /[^\/]+/ }, as: :user_by_auth0_deprecated

      get 'users/:auth0_id/schools',
          to: 'users#schools_by_path',
          constraints: { auth0_id: /[^\/]+/ }, as: :user_schools_by_auth0_deprecated

      get 'users/:auth0_id/onboarding_status',
          to: 'users#onboarding_status_by_path',
          constraints: { auth0_id: /[^\/]+/ }, as: :user_onboarding_by_auth0_deprecated

      # =========================================================
      # USERS (Internal DB Only)
      # =========================================================
      resources :users, only: [:create] do
        member do
          # ⚠️ INTERNAL MONGODB _id ONLY — never pass auth0_id here
          get   :roles
          post  :add_role
          get   :onboarding_required

          # NOTE: patch :update_profile REMOVED from here to prevent
          # Rails from matching /users/google-oauth2|xxx/update_profile

          resource :onboarding_status, controller: :onboarding_statuses, only: [:show, :update] do
            post :complete_step, :skip_step, :reset
          end
        end
      end

      # =========================================================
      # PARENTS & LEARNERS
      # =========================================================
      scope :parents, controller: :my_learners do
        get :my_learners, action: :index  # ?auth0_id=
        get :profile                      # ?auth0_id=
      end

      resources :learner_links, only: [:create]

      # =========================================================
      # INVITES / INVITATIONS
      # =========================================================
      resources :invites, only: [:create, :show, :update] do
        member { post :generate_pr_code; post :create_short_link }
      end

      resources :invitations, param: :token, only: [:create] do
        collection { post :verify, :bulk_create }
      end

      resources :learner_invitations do
        member { post :accept, :decline, :cancel, :resend }
        collection { get :pending, :expired; get 'by_grade/:grade_id', action: :by_grade }
      end

      resources :teacher_invitations do
        member { post :accept, :decline, :cancel, :resend }
        collection { get :pending, :expired; get 'by_school/:school_id', action: :by_school }
      end

      # =========================================================
      # SCHOOLS & DEBT MANAGEMENT
      # =========================================================
      resources :schools do
        member do
          get :admins, :teachers, :parents
          get 'parents/:parent_id', to: 'schools#show_parent'
        end
        collection { get :search }

        resources :students
        resources :grades,   only: [:index, :create]
        resources :learners, only: [:index]
        resources :pr_codes, only: [:index, :show, :create, :destroy]
        resources :transactions, only: [:index, :show, :create, :update, :destroy] do
          collection { get :pending, :completed }
        end

        scope :debt_management, controller: :debt_management do
          get :debt_summary, action: :summary
          get :debtors, action: :index
          get 'accounts/:account_id', action: :show_account
          get 'accounts/:account_id/payments', action: :account_payments
          post 'accounts/:account_id/payments', action: :create_payment
        end
      end

      # =========================================================
      # GRADES & TEACHER ASSIGNMENTS
      # =========================================================
      resources :grades, only: [:show, :update, :destroy] do
        member do
          get :learners, :teachers, :stats
          post :invite_learner, :invite_teacher
          post   'learners/:learner_id', action: :add_learner
          delete 'learners/:learner_id', action: :remove_learner
        end

        resources :teacher_assignments, controller: :teacher_grade_assignments do
          member { patch :activate, :deactivate, :terminate, :suspend }
        end
      end

      resources :teacher_grade_assignments do
        member { patch :activate, :deactivate, :terminate, :suspend }
        collection do
          get 'by_teacher/:teacher_id', action: :by_teacher
          get 'by_grade/:grade_id', action: :by_grade
          get 'by_school/:school_id', action: :by_school
        end
      end

      # =========================================================
      # ACADEMIC DATA (LEARNERS, SUBJECTS, ASSESSMENTS)
      # =========================================================
      resources :learners do
        collection { post :bulk_upload; get :search, :export, :statistics }
        member { patch :graduate, :transfer, :activate, :deactivate; get :history, :grades }
      end

      resources :subjects do
        collection { post :bulk_upload; get :search }
        member { patch :activate, :deactivate }
      end

      resources :assessments do
        collection { post :bulk_upload; get :search, :upcoming, :completed }
        member { patch :publish, :unpublish; post :duplicate }
        resources :results, only: [:index, :show, :create, :update, :destroy] do
          collection { post :bulk_upload; get :statistics, :export, :search }
        end
      end

      resources :results do
        collection { post :bulk_upload; get :search, :statistics, :export }
        member { patch :approve, :reject }
      end

      # =========================================================
      # SYSTEM & UTILITIES
      # =========================================================
      resources :transactions, only: [:index, :show, :create, :update, :destroy] do
        member { post :process_payment }
      end

      resources :request_accesses do
        collection { get 'school/:school_id', action: :by_school; get :pending_requests, :approved_schools; post :approve, :reject }
        member { get :users_by_roles }
      end

      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:index, :create]
      end

      namespace :dashboard do
        get :overview, :learner_statistics, :school_statistics,
            :assessment_statistics, :performance_trends, :grade_statistics
      end

      namespace :reports do
        get :learner_performance, :school_performance, :grade_performance, :subject_performance
        post :generate_custom
        get 'download/:id', action: :download
      end

      namespace :import_export do
        post :import_learners, :import_schools, :import_grades, :import_results
        get :export_learners, :export_schools, :export_grades, :export_results
        get 'template/:type', action: :download_template
      end

      scope :auth, controller: :authentication do
        post :login, :logout, :refresh, :forgot_password, :reset_password
      end

      namespace :admin do
        get :system_info, :audit_logs, :backup_status
        post :backup_database
        patch :system_settings, action: :update_system_settings
      end

      resources :uploads, only: [:create, :show, :destroy]
      resources :notifications do
        collection { patch :mark_all_read; get :unread_count }
        member { patch :mark_read, :mark_unread }
      end

      namespace :public do
        namespace :invitations do
          post 'learner/:token/accept', action: :accept_learner_invitation
          post 'teacher/:token/accept', action: :accept_teacher_invitation
          get  'learner/:token', action: :show_learner_invitation
          get  'teacher/:token', action: :show_teacher_invitation
        end
      end

      get 'health', to: 'home#health'
      scope :pr_codes, controller: :pr_codes do
        post :validate, :use
      end
    end
  end

  # =========================================================
  # GLOBAL ROUTES
  # =========================================================
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root 'api/v1/home#index'
  get 'health', to: 'api/v1/home#health'
  get 'api/docs', to: 'api/v1/documentation#index'
  get 'invitations/:token/verify_with_details', to: 'api/v1/invitations#verify_with_details'
end