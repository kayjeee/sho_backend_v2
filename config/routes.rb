# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

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
      resources :users, param: :auth0_id do
        collection do
          get   :me                  # token-based
          get   :onboarding_status
          get   :schools
        end
        member do
          put   :update_roles
          post  :add_school
          patch :update_profile

          # Internal DB ID compatibility
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

      # =========================================================
      # USERS - Backward Compatibility (DEPRECATED)
      # =========================================================
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
        member do
          post :generate_pr_code
          post :create_short_link
        end
      end

      resources :invitations, param: :token, only: [:create, :show] do
        member do
          get :verify_with_details   # GET /api/v1/invitations/:token/verify_with_details
        end
        collection do
          post :verify               # POST /api/v1/invitations/verify
          post :bulk_create          # POST /api/v1/invitations/bulk_create
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
          get :verify                # GET /api/v1/learner_invitations/verify?token=...
          get :pending
          get :expired
          get 'by_grade/:grade_id', action: :by_grade
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
          get :verify                # GET /api/v1/teacher_invitations/verify?token=...
          get :pending
          get :expired
          get 'by_school/:school_id', action: :by_school
        end
      end

      # =========================================================
      # SCHOOLS & DEBT MANAGEMENT
      # =========================================================
      resources :schools do
        member do
          get :admins
          get :teachers
          get :parents
          get :directory
          get 'teachers/:teacher_id', to: 'schools#show_teacher'
          get 'parents/:parent_id', to: 'schools#show_parent'
        end
        collection do
          get :search
        end

        resources :students
        resources :grades,   only: [:index, :create]
        resources :learners, only: [:index]
        resources :pr_codes, only: [:index, :show, :create, :destroy]
        resources :transactions, only: [:index, :show, :create, :update, :destroy] do
          collection do
            get :pending
            get :completed
          end
        end

        scope :debt_management, controller: :debt_management do
          get  :debt_summary,                       action: :summary
          get  :debtors,                            action: :index
          get  'accounts/:account_id',              action: :show_account
          get  'accounts/:account_id/payments',     action: :account_payments
          post 'accounts/:account_id/payments',     action: :create_payment
        end
      end

      # =========================================================
      # GRADES & TEACHER ASSIGNMENTS
      # =========================================================
      resources :grades, only: [:show, :update, :destroy] do
        member do
          get    :learners
          get    :teachers
          get    :stats
          post   :invite_learner
          post   :invite_teacher
          post   'learners/:learner_id', action: :add_learner
          delete 'learners/:learner_id', action: :remove_learner
        end

        resources :teacher_assignments, controller: :teacher_grade_assignments do
          member do
            patch :activate
            patch :deactivate
            patch :terminate
            patch :suspend
          end
        end
      end

      resources :teacher_grade_assignments do
        member do
          patch :activate
          patch :deactivate
          patch :terminate
          patch :suspend
        end
        collection do
          get 'by_teacher/:teacher_id', action: :by_teacher
          get 'by_grade/:grade_id',     action: :by_grade
          get 'by_school/:school_id',   action: :by_school
        end
      end

      # =========================================================
      # ACADEMIC DATA (LEARNERS, SUBJECTS, ASSESSMENTS)
      # =========================================================
      resources :learners do
        collection do
          post :bulk_upload
          get :search
          get :export
          get :statistics
        end
        member do
          patch :graduate
          patch :transfer
          patch :activate
          patch :deactivate
          get :history
          get :grades
        end
      end

      resources :subjects do
        collection do
          post :bulk_upload
          get :search
        end
        member do
          patch :activate
          patch :deactivate
        end
      end

      resources :assessments do
        collection do
          post :bulk_upload
          get :search
          get :upcoming
          get :completed
        end
        member do
          patch :publish
          patch :unpublish
          post :duplicate
        end
        resources :results, only: [:index, :show, :create, :update, :destroy] do
          collection do
            post :bulk_upload
            get :statistics
            get :export
            get :search
          end
        end
      end

      resources :results do
        collection do
          post :bulk_upload
          get :search
          get :statistics
          get :export
        end
        member do
          patch :approve
          patch :reject
        end
      end

      # =========================================================
      # SYSTEM & UTILITIES
      # =========================================================
      resources :transactions, only: [:index, :show, :create, :update, :destroy] do
        member { post :process_payment }
      end

      resources :request_accesses do
        collection do
          get  'school/:school_id', action: :by_school
          get  :pending_requests
          get  :approved_schools
          post :approve
          post :reject
        end
        member { get :users_by_roles }
      end

      resources :conversations, only: [:index, :show, :create, :destroy] do
        member do
          put :read
          get :participants
          put :participants
        end
        resources :messages, only: [:index, :create]
      end

      namespace :dashboard do
        get :overview
        get :learner_statistics
        get :school_statistics
        get :assessment_statistics
        get :performance_trends
        get :grade_statistics
      end

      namespace :reports do
        get  :learner_performance
        get  :school_performance
        get  :grade_performance
        get  :subject_performance
        post :generate_custom
        get  'download/:id', action: :download
      end

      namespace :import_export do
        post :import_learners
        post :import_schools
        post :import_grades
        post :import_results
        get  :export_learners
        get  :export_schools
        get  :export_grades
        get  :export_results
        get  'template/:type', action: :download_template
      end

      scope :auth, controller: :authentication do
        post :login
        post :logout
        post :refresh
        post :forgot_password
        post :reset_password
      end

      namespace :admin do
        get   :system_info
        get   :audit_logs
        get   :backup_status
        post  :backup_database
        patch :system_settings, action: :update_system_settings
      end

      resources :uploads, only: [:index, :create, :show, :destroy]

      resources :notifications do
        collection do
          patch :mark_all_read
          get :unread_count
        end
        member do
          patch :mark_read
          patch :mark_unread
        end
      end

      namespace :public do
        resources :invitations, only: [] do
          collection do
            post 'learner/:token/accept', action: :accept_learner_invitation
            post 'teacher/:token/accept', action: :accept_teacher_invitation
            get  'learner/:token',        action: :show_learner_invitation
            get  'teacher/:token',        action: :show_teacher_invitation
          end
        end
      end

      get 'health', to: 'home#health'

      scope :pr_codes, controller: :pr_codes do
        post :validate
        post :use
      end

    end
  end

  # =========================================================
  # GLOBAL ROUTES
  # =========================================================
  root 'api/v1/home#index'
  get 'health',    to: 'api/v1/home#health'
  get 'api/docs',  to: 'api/v1/documentation#index'
end
