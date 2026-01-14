Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do

      # ================= ADMIN USERS =================
      get 'admin_users/schools_for_admin', to: 'admin_users#schools_for_admin'

      # ================= USERS =================
      resources :users do
        member do
          get :roles
          post :add_role
          patch :update_roles
          patch :update_profile
          get :schools
          patch :add_school
          get :onboarding_required

          resource :onboarding_status,
                   controller: 'onboarding_statuses',
                   only: [:show, :update] do
            post :complete_step
            post :skip_step
            post :reset
          end
        end

        collection do
          get :me
        end
      end

      # ================= PARENTS & LEARNERS =================
      get 'parents/:auth0_id/my_learners',
          to: 'my_learners#index',
          constraints: { auth0_id: /[^\/]+/ }

      get 'parents/:auth0_id/profile',
          to: 'my_learners#profile',
          constraints: { auth0_id: /[^\/]+/ }

      post 'learner_links', to: 'learner_links#create'

      # ================= INVITES =================
      resources :invites, only: [:create, :show, :update] do
        member do
          post :generate_pr_code
          post :create_short_link
        end
      end

      # ================= SCHOOLS =================
      resources :schools do
        member do
          get :admins
          get :teachers
          get :parents
          get 'parents/:parent_id', to: 'schools#show_parent'

          get 'debt_summary', to: 'debt_management#summary'
          get 'debtors', to: 'debt_management#index'
          get 'accounts/:account_id', to: 'debt_management#show_account'
          get 'accounts/:account_id/payments', to: 'debt_management#account_payments'
          post 'accounts/:account_id/payments', to: 'debt_management#create_payment'
        end

        collection do
          get :search
        end

        resources :students
        resources :grades, only: [:index, :create]
        resources :learners, only: [:index]

        resources :transactions do
          collection do
            get :pending
            get :completed
          end
        end

        resources :pr_codes, only: [:index, :show, :create, :destroy]
      end

      # ================= PR CODES =================
      post 'pr_codes/validate', to: 'pr_codes#validate'
      post 'pr_codes/use', to: 'pr_codes#use'

      # ================= GRADES =================
      resources :grades, only: [:show, :update, :destroy] do
        member do
          get :learners
          get :teachers
          get :stats
          post :invite_learner
          post :invite_teacher
        end

        post   'learners/:learner_id', to: 'grades#add_learner'
        delete 'learners/:learner_id', to: 'grades#remove_learner'

        resources :teacher_assignments,
                  controller: 'teacher_grade_assignments' do
          member do
            patch :activate
            patch :deactivate
            patch :terminate
            patch :suspend
          end
        end
      end

      # ================= INVITATIONS =================
      resources :invitations, param: :token, only: [:create] do
        collection do
          post :verify
          post :bulk_create   # ✅ Added bulk_create here
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
          get :pending
          get :expired
          get 'by_school/:school_id', action: :by_school
        end
      end

      # ================= TEACHER GRADE ASSIGNMENTS =================
      resources :teacher_grade_assignments do
        member do
          patch :activate
          patch :deactivate
          patch :terminate
          patch :suspend
        end

        collection do
          get 'by_teacher/:teacher_id', action: :by_teacher
          get 'by_grade/:grade_id',   action: :by_grade
          get 'by_school/:school_id', action: :by_school
        end
      end

      # ================= LEARNERS =================
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

      # ================= TRANSACTIONS =================
      resources :transactions do
        member do
          post :process_payment
        end
      end

      # ================= REQUEST ACCESS =================
      resources :request_accesses do
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

      # ================= CONVERSATIONS =================
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:index, :create]
      end

      # ================= ASSESSMENTS =================
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

        resources :results do
          collection do
            post :bulk_upload
            get  :statistics
            get  :export
            get  :search
          end
        end
      end

      # ================= RESULTS =================
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

      # ================= SUBJECTS =================
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

      # ================= DASHBOARD =================
      namespace :dashboard do
        get :overview
        get :learner_statistics
        get :school_statistics
        get :assessment_statistics
        get :performance_trends
        get :grade_statistics
      end

      # ================= REPORTS =================
      namespace :reports do
        get :learner_performance
        get :school_performance
        get :grade_performance
        get :subject_performance
        post :generate_custom
        get 'download/:id', action: :download
      end

      # ================= IMPORT / EXPORT =================
      namespace :import_export do
        post :import_learners
        post :import_schools
        post :import_grades
        post :import_results
        get  :export_learners
        get  :export_schools
        get  :export_grades
        get  :export_results
        get 'template/:type', action: :download_template
      end

      # ================= AUTH =================
      post 'auth/login',          to: 'authentication#login'
      post 'auth/logout',         to: 'authentication#logout'
      post 'auth/refresh',        to: 'authentication#refresh'
      post 'auth/forgot_password',to: 'authentication#forgot_password'
      post 'auth/reset_password', to: 'authentication#reset_password'

      # ================= ADMIN =================
      namespace :admin do
        get  :system_info
        get  :audit_logs
        post :backup_database
        get  :backup_status
        patch :system_settings, to: 'admin#update_system_settings'
      end

      # ================= UPLOADS =================
      post   'uploads',     to: 'uploads#create'
      get    'uploads/:id', to: 'uploads#show'
      delete 'uploads/:id', to: 'uploads#destroy'

      # ================= NOTIFICATIONS =================
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

      # ================= PUBLIC INVITATIONS =================
      post 'public/invitations/learner/:token/accept',
           to: 'public/invitations#accept_learner_invitation'

      post 'public/invitations/teacher/:token/accept',
           to: 'public/invitations#accept_teacher_invitation'

      get 'public/invitations/learner/:token',
          to: 'public/invitations#show_learner_invitation'

      get 'public/invitations/teacher/:token',
          to: 'public/invitations#show_teacher_invitation'

      # ================= HEALTH =================
      get 'health', to: 'home#health'
    end

    namespace :v2 do
      # future endpoints
    end
  end

  # ================= GLOBAL =================
  root 'api/v1/home#index'
  get 'health', to: 'api/v1/home#health'

  get 'invitations/:token/verify_with_details',
      to: 'api/v1/invitations#verify_with_details'

  get 'api/docs', to: 'api/v1/documentation#index'
end