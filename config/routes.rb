# config/routes.rb
Rails.application.routes.draw do
  # Root level school routes for requests missing /api/v1 prefix
  get 'schools/:school_id/grades', to: 'api/v1/grades#index'
  get 'grades/:id', to: 'api/v1/grades#show'

  namespace :api, defaults: { format: :json } do
    namespace :admin do
      resources :grades, only: [:index, :show]
      resources :learners, only: [:index]
    end

    # Explicit alias for frontend compatibility
    get 'admin/grades', to: 'admin/grades#index'

    # Fallback scope to capture Auth0/NextJS lifecycle pings
    scope :auth do
      match 'login', to: 'auth#login', via: [:get, :post]
      match 'me', to: 'auth#me', via: [:get]
    end

    namespace :v1 do
      # Handle double-prefixed requests from some frontend configurations
      get 'api/admin/grades', to: '/api/admin/grades#index'

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
        patch :update_profile      # ?auth0_id=
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
          
          resource :onboarding_status, controller: :onboarding_statuses, only: [:show, :update] do
            post :complete_step
            post :skip_step
            post :reset
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
        member do
          post :generate_pr_code
          post :create_short_link
        end
      end

      # Invitations Routes (NEW - for POST /api/v1/invitations)
      resources :invitations, param: :token, only: [:create] do
        collection do
          post :verify
          post :bulk_create
        end
      end

      resources :learner_invitations, only: [:index, :show, :update, :destroy] do
        member do
          post :accept
          post :decline
          post :cancel
          post :resend
        end

        collection do
          get :pending
          get :expired
          get 'by_grade/:grade_id', action: :by_grade
        end
      end

      resources :teacher_invitations, only: [:index, :show, :update, :destroy] do
        member do
          post :accept
          post :decline
          post :cancel
          post :resend
        end

        collection do
          get :pending
          get :expired
          get 'by_school/:school_id', action: :by_school
        end
      end

      # =========================================================
      # SCHOOLS & DEBT MANAGEMENT
      # =========================================================
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
        get :global_search, on: :member
        resources :students, only: [:index, :show, :create, :update, :destroy]
        resources :grades, only: [:index, :create] do
          resources :classes, controller: 'classes' do
            member do
              post :assign_teacher
              post :move_learner
              get :learners
              get :stats
            end
          end

          member do
            get :learners
            get :teachers
            get :stats
          end
        end
        resources :learners, only: [:index]
        resources :transactions, only: [:index, :show, :create, :update, :destroy] do
          collection do
            get :pending
            get :completed
          end
        end

        # PR Code routes nested under schools
        resources :pr_codes, only: [:index, :show, :create, :destroy]
      end

      # =========================================================
      # GRADES & TEACHER ASSIGNMENTS
      # =========================================================
      resources :grades, only: [:index, :show, :update, :destroy] do
        resources :classes, only: [:index, :create], controller: 'classes'
        resources :learners, only: [:index], controller: 'grades/learners'
        
        member do
          get :learners
          get :teachers
          get :stats
          get :hierarchy
          post :invite_learner
          post :invite_teacher
        end

        post 'learners/:learner_id', to: 'grades#add_learner'
        delete 'learners/:learner_id', to: 'grades#remove_learner'

        resources :teacher_assignments, only: [:index, :create, :update, :destroy],
                                        controller: 'teacher_grade_assignments' do
          member do
            patch :activate
            patch :deactivate
            patch :terminate
            patch :suspend
          end
        end
      end

      resources :teacher_grade_assignments, only: [:index, :show, :create, :update, :destroy] do
        member do
          patch :activate
          patch :deactivate
          patch :terminate
          patch :suspend
        end

        collection do
          get 'by_teacher/:teacher_id', action: :by_teacher
          get 'by_grade/:grade_id', action: :by_grade
          get 'by_school/:school_id', action: :by_school
        end
      end

      # =========================================================
      # ACADEMIC DATA (LEARNERS, SUBJECTS, ASSESSMENTS)
      # =========================================================
      resources :learners, only: [:index, :show, :create, :update, :destroy] do
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

      resources :subjects, only: [:index, :show, :create, :update, :destroy] do
        collection do
          post :bulk_upload
          get :search
        end

        member do
          patch :activate
          patch :deactivate
        end
      end

      resources :assessments, only: [:index, :show, :create, :update, :destroy] do
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

      resources :results, only: [:index, :show, :create, :update, :destroy] do
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

      # =========================================================
      # CONVERSATIONS
      # =========================================================
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:create, :index]
      end

      # =========================================================
      # SYSTEM & UTILITIES
      # =========================================================
      
      # PR Code validation and usage endpoints
      post 'pr_codes/validate', to: 'pr_codes#validate'
      post 'pr_codes/use', to: 'pr_codes#use'

      # DASHBOARD
      namespace :dashboard do
        get 'overview', to: 'dashboard#overview'
        get 'learner_statistics', to: 'dashboard#learner_statistics'
        get 'school_statistics', to: 'dashboard#school_statistics'
        get 'assessment_statistics', to: 'dashboard#assessment_statistics'
        get 'performance_trends', to: 'dashboard#performance_trends'
        get 'grade_statistics', to: 'dashboard#grade_statistics'
      end

      # REPORTS
      namespace :reports do
        get 'learner_performance', to: 'reports#learner_performance'
        get 'school_performance', to: 'reports#school_performance'
        get 'grade_performance', to: 'reports#grade_performance'
        get 'subject_performance', to: 'reports#subject_performance'
        post 'generate_custom', to: 'reports#generate_custom'
        get 'download/:id', to: 'reports#download'
      end

      # IMPORT/EXPORT
      namespace :import_export do
        post 'import_learners', to: 'import_export#import_learners'
        post 'import_schools', to: 'import_export#import_schools'
        post 'import_grades', to: 'import_export#import_grades'
        post 'import_results', to: 'import_export#import_results'
        get 'export_learners', to: 'import_export#export_learners'
        get 'export_schools', to: 'import_export#export_schools'
        get 'export_grades', to: 'import_export#export_grades'
        get 'export_results', to: 'import_export#export_results'
        get 'template/:type', to: 'import_export#download_template'
      end

      # AUTH
      scope :auth, controller: :authentication do
        post :login
        post :logout
        post :refresh
        post :forgot_password
        post :reset_password
      end

      # ADMIN
      namespace :admin do
        get 'system_info', to: 'admin#system_info'
        get 'audit_logs', to: 'admin#audit_logs'
        post 'backup_database', to: 'admin#backup_database'
        get 'backup_status', to: 'admin#backup_status'
        patch 'system_settings', to: 'admin#update_system_settings'
      end

      # UPLOADS
      resources :uploads, only: [:create, :show, :destroy]

      # NOTIFICATIONS
      resources :notifications, only: [:index, :show, :create, :update, :destroy] do
        collection do
          patch :mark_all_read
          get :unread_count
        end

        member do
          patch :mark_read
          patch :mark_unread
        end
      end

      # PUBLIC INVITATIONS (unauthenticated)
      namespace :public do
        namespace :invitations do
          post 'learner/:token/accept', action: :accept_learner_invitation
          post 'teacher/:token/accept', action: :accept_teacher_invitation
          get  'learner/:token', action: :show_learner_invitation
          get  'teacher/:token', action: :show_teacher_invitation
        end
      end

      # HEALTH
      get 'health', to: 'home#health'
    end

    # Future versioning
    namespace :v2 do
      # future API endpoints
    end
  end

  # =========================================================
  # GLOBAL ROUTES
  # =========================================================
  
  # Root route
  root 'api/v1/home#index'
  
  # Global health
  get 'up', to: 'api/v1/home#health'
  get 'health', to: 'api/v1/home#health'

  # API docs
  get 'api/docs', to: 'api/v1/documentation#index'
  
  # Invitation verification with details (unauthenticated)
  get 'invitations/:token/verify_with_details', to: 'api/v1/invitations#verify_with_details'
end