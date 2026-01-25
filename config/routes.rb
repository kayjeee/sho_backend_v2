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
      # USERS (Auth0-safe — NO auth0_id in URL paths)
      # =========================================================
      # Auth0-safe endpoints (query params only) - PREFERRED
      scope :users, controller: :users do
        get  :show          # ?auth0_id=
        get  :schools       # ?auth0_id=
        get  :me            # token-based
        put  :update_roles  # ?auth0_id=
        post :add_school    # ?auth0_id=
        get  :onboarding_status  # ?auth0_id=
      end

      # =========================================================
      # USERS - Backward Compatibility (DEPRECATED)
      # =========================================================
      # Support old path-based format during migration
      # These will be removed in future versions
      get 'users/:auth0_id', 
          to: 'users#show_by_path',
          constraints: { auth0_id: /[^\/]+/ },
          as: :user_by_auth0_deprecated

      get 'users/:auth0_id/schools',
          to: 'users#schools_by_path',
          constraints: { auth0_id: /[^\/]+/ },
          as: :user_schools_by_auth0_deprecated

      get 'users/:auth0_id/onboarding_status',
          to: 'users#onboarding_status_by_path',
          constraints: { auth0_id: /[^\/]+/ },
          as: :user_onboarding_by_auth0_deprecated

      # Internal DB-only routes (uses internal MongoDB _id)
      resources :users, only: [:create] do
        member do
          # ⚠️ INTERNAL ID ONLY — never auth0_id
          get   :roles
          post  :add_role
          patch :update_profile
          get   :onboarding_required

          resource :onboarding_status,
                   controller: :onboarding_statuses,
                   only: [:show, :update] do
            post :complete_step
            post :skip_step
            post :reset
          end
        end
      end

      # =========================================================
      # PARENTS & LEARNERS (Auth0-safe)
      # =========================================================
      scope :parents, controller: :my_learners do
        get :my_learners, action: :index  # ?auth0_id=
        get :profile                      # ?auth0_id=
      end

      resources :learner_links, only: [:create]

      # =========================================================
      # INVITES
      # =========================================================
      resources :invites, only: [:create, :show, :update] do
        member do
          post :generate_pr_code
          post :create_short_link
        end
      end

      # =========================================================
      # SCHOOLS
      # =========================================================
      resources :schools do
        member do
          get :admins
          get :teachers
          get :parents
          get 'parents/:parent_id', to: 'schools#show_parent', as: :show_parent
        end

        collection do
          get :search
        end

        # Nested resources
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

        # Debt management
        scope :debt_management, controller: :debt_management do
          get :debt_summary, action: :summary
          get :debtors, action: :index
          get 'accounts/:account_id', action: :show_account, as: :debt_account
          get 'accounts/:account_id/payments', action: :account_payments, as: :debt_account_payments
          post 'accounts/:account_id/payments', action: :create_payment
        end
      end

      # =========================================================
      # PR CODES
      # =========================================================
      scope :pr_codes, controller: :pr_codes do
        post :validate
        post :use
      end

      # =========================================================
      # GRADES
      # =========================================================
      resources :grades, only: [:show, :update, :destroy] do
        member do
          get  :learners
          get  :teachers
          get  :stats
          post :invite_learner
          post :invite_teacher
          
          # Learner management
          post   'learners/:learner_id', action: :add_learner, as: :add_learner_to
          delete 'learners/:learner_id', action: :remove_learner, as: :remove_learner_from
        end

        # Teacher assignments
        resources :teacher_assignments,
                  controller: :teacher_grade_assignments do
          member do
            patch :activate
            patch :deactivate
            patch :terminate
            patch :suspend
          end
        end
      end

      # =========================================================
      # INVITATIONS
      # =========================================================
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
          get 'by_grade/:grade_id', action: :by_grade, as: :by_grade
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
          get 'by_school/:school_id', action: :by_school, as: :by_school
        end
      end

      # =========================================================
      # TEACHER GRADE ASSIGNMENTS
      # =========================================================
      resources :teacher_grade_assignments do
        member do
          patch :activate
          patch :deactivate
          patch :terminate
          patch :suspend
        end

        collection do
          get 'by_teacher/:teacher_id', action: :by_teacher, as: :by_teacher
          get 'by_grade/:grade_id', action: :by_grade, as: :by_grade
          get 'by_school/:school_id', action: :by_school, as: :by_school
        end
      end

      # =========================================================
      # LEARNERS
      # =========================================================
      resources :learners do
        collection do
          post :bulk_upload
          get  :search
          get  :export
          get  :statistics
        end

        member do
          patch :graduate
          patch :transfer
          patch :activate
          patch :deactivate
          get   :history
          get   :grades
        end
      end

      # =========================================================
      # TRANSACTIONS
      # =========================================================
      resources :transactions, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :process_payment
        end
      end

      # =========================================================
      # REQUEST ACCESS
      # =========================================================
      resources :request_accesses do
        collection do
          get 'school/:school_id', action: :by_school, as: :by_school
          get :pending_requests
          get :approved_schools
          post :approve
          post :reject
        end

        member do
          get :users_by_roles
        end
      end

      # =========================================================
      # CONVERSATIONS
      # =========================================================
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:index, :create]
      end

      # =========================================================
      # ASSESSMENTS
      # =========================================================
      resources :assessments do
        collection do
          post :bulk_upload
          get  :search
          get  :upcoming
          get  :completed
        end

        member do
          patch :publish
          patch :unpublish
          post  :duplicate
        end

        resources :results, only: [:index, :show, :create, :update, :destroy] do
          collection do
            post :bulk_upload
            get  :statistics
            get  :export
            get  :search
          end
        end
      end

      # =========================================================
      # RESULTS
      # =========================================================
      resources :results do
        collection do
          post :bulk_upload
          get  :search
          get  :statistics
          get  :export
        end

        member do
          patch :approve
          patch :reject
        end
      end

      # =========================================================
      # SUBJECTS
      # =========================================================
      resources :subjects do
        collection do
          post :bulk_upload
          get  :search
        end

        member do
          patch :activate
          patch :deactivate
        end
      end

      # =========================================================
      # DASHBOARD
      # =========================================================
      namespace :dashboard do
        get :overview
        get :learner_statistics
        get :school_statistics
        get :assessment_statistics
        get :performance_trends
        get :grade_statistics
      end

      # =========================================================
      # REPORTS
      # =========================================================
      namespace :reports do
        get  :learner_performance
        get  :school_performance
        get  :grade_performance
        get  :subject_performance
        post :generate_custom
        get  'download/:id', action: :download, as: :download
      end

      # =========================================================
      # IMPORT / EXPORT
      # =========================================================
      namespace :import_export do
        post :import_learners
        post :import_schools
        post :import_grades
        post :import_results
        get  :export_learners
        get  :export_schools
        get  :export_grades
        get  :export_results
        get  'template/:type', action: :download_template, as: :download_template
      end

      # =========================================================
      # AUTHENTICATION
      # =========================================================
      scope :auth, controller: :authentication do
        post :login
        post :logout
        post :refresh
        post :forgot_password
        post :reset_password
      end

      # =========================================================
      # ADMIN
      # =========================================================
      namespace :admin do
        get  :system_info
        get  :audit_logs
        post :backup_database
        get  :backup_status
        patch :system_settings, action: :update_system_settings
      end

      # =========================================================
      # UPLOADS
      # =========================================================
      resources :uploads, only: [:create, :show, :destroy]

      # =========================================================
      # NOTIFICATIONS
      # =========================================================
      resources :notifications do
        collection do
          patch :mark_all_read
          get   :unread_count
        end

        member do
          patch :mark_read
          patch :mark_unread
        end
      end

      # =========================================================
      # PUBLIC INVITATIONS
      # =========================================================
      namespace :public do
        namespace :invitations do
          post   'learner/:token/accept', action: :accept_learner_invitation, as: :accept_learner
          post   'teacher/:token/accept', action: :accept_teacher_invitation, as: :accept_teacher
          get    'learner/:token', action: :show_learner_invitation, as: :show_learner
          get    'teacher/:token', action: :show_teacher_invitation, as: :show_teacher
        end
      end

      # =========================================================
      # HEALTH CHECK
      # =========================================================
      get 'health', to: 'home#health'
    end

    # =========================================================
    # API V2 (Future)
    # =========================================================
    namespace :v2 do
      # Future endpoints
    end
  end

  # =========================================================
  # GLOBAL ROUTES
  # =========================================================
  root 'api/v1/home#index'
  get 'health', to: 'api/v1/home#health'
  get 'api/docs', to: 'api/v1/documentation#index'

  # Global invitation verification
  get 'invitations/:token/verify_with_details',
      to: 'api/v1/invitations#verify_with_details',
      as: :verify_invitation_with_details
end