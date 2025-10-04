# New Application Architecture and File Structure Plan

This section outlines the proposed architectural changes and file structure for the Ruby on Rails school CRM application, aiming to meet NASA standards for maintainability, scalability, and ease of onboarding for junior developers. The core principles guiding this redesign are:

1.  **Strict Separation of Concerns:** Each component should have a single, well-defined responsibility.
2.  **Modularity:** Components should be self-contained and loosely coupled, allowing for independent development, testing, and deployment.
3.  **Manageable File Sizes:** Adherence to the user's requirement of keeping files under 500 lines, promoting readability and reducing cognitive load.
4.  **Clarity and Consistency:** Consistent naming conventions, clear directory structures, and predictable patterns to facilitate understanding and reduce onboarding time for new developers.
5.  **Testability:** Design choices that inherently support comprehensive testing at all levels (unit, integration, system).

## General Architectural Principles

To achieve these goals, we will adopt a more service-oriented approach within the Rails application, moving complex business logic out of controllers and models into dedicated service objects, form objects, and potentially policy objects. This aligns with the NASA 


standards of modularity and restricting function scope [1].

### 1. Service Objects

Service objects will encapsulate specific business processes or use cases. Instead of having large controller actions or model callbacks that handle multiple steps, a service object will orchestrate these steps. This keeps controllers thin and focused on handling HTTP requests and responses, and models focused on data persistence and basic validations. For example, instead of a `SchoolsController` handling all the logic for adding a student to a school, a `School::AddStudentService` could be responsible for that specific operation.

### 2. Form Objects

Form objects will handle complex form submissions, validations, and data transformations. This is particularly useful when a form spans multiple models or requires custom validation logic that doesn't belong in a single model. This helps keep models lean and focused on their core responsibilities.

### 3. Policy Objects (or Authorizers)

Policy objects will centralize authorization logic. Instead of scattering `if current_user.admin?` checks throughout controllers and views, a dedicated policy object (e.g., `SchoolPolicy`) will determine if a user has permission to perform a certain action on a given resource. This improves readability, testability, and maintainability of authorization rules.

### 4. Value Objects

For simple data structures that represent a concept but don't require persistence (e.g., a `Money` object with amount and currency), value objects can be used. This improves type safety and makes the code more expressive.

### 5. Decorators/Presenters

These objects will handle view-specific logic and data formatting, keeping views clean and free of complex Ruby code. This separates the presentation layer from the business logic.

## Proposed File Structure Changes

The current `app/controllers/api/v1` structure is a good starting point, but we will introduce new directories to house the service, form, and policy objects, promoting better organization and adherence to the 500-line rule. The goal is to make the project structure intuitive for new developers, aligning with the NASA standard for clarity and consistency.

```
SHO_BACKEND
├── .kamal
├── app
│   ├── assets
│   ├── channels
│   ├── controllers
│   │   ├── api
│   │   │   └── v1
│   │   │      
│   │   │       ├── concerns # For controller-specific concerns
│   │   │       ├── schools_controller.rb # Smaller, focused controllers
│   │   │       ├── users_controller.rb
│   │   │       ├── grades_controller.rb
│   │   │       ├── learners_controller.rb
│   │   │       ├── request_access_controller.rb
│   │   │       ├── admin_users_controller.rb
│   │   │       ├── accounts_controller.rb
│   │   │       └── ...
│   │   ├── concerns
│   │   ├── application_controller.rb
│   │   ├── errors_controller.rb
│   │   ├── private_controller.rb
│   │   └── public_controller.rb
│   ├── jobs
│   ├── lib
│   │   └── services # For general utility services not tied to a specific domain
│   ├── mailers
│   ├── models
│   │   ├── concerns # For model-specific concerns
│   │   ├── account.rb
│   │   ├── grade.rb
│   │   ├── learner.rb
│   │   ├── school.rb
│   │   ├── user.rb
│   │   ├── user_school.rb
│   │   ├── teacher_grade_assignment.rb
│   │   ├── teacher_invitation.rb
│   │   ├── learner_invitation.rb
│   │   ├── request_access.rb
│   │   ├── message.rb
│   │   └── ...
│   ├── forms # New directory for form objects
│   │   ├── school_forms # Namespace for school-related forms
│   │   │   └── add_student_form.rb
│   │   └── ...
│   ├── policies # New directory for policy objects (authorization)
│   │   ├── school_policy.rb
│   │   └── ...
│   services/
│   │   └── user_services/
│   │       ├── add_school_service.rb
│   │       ├── create_user_service.rb
│   │       ├── fetch_schools_service.rb
│   │       └── update_roles_service.rb
│   │   └── grade_services/
│   │       └── create_grade_service.rb
│   │       └── delete_grade_service.rb
│   │       └── invite_learner_service.rb
│   │       └── invite_teacher_service.rb
│   │       └── update_grade_service.rb
│   │   └── learner_services/
│   │       └── bulk_upload_service.rb
│   │   ├── school_services # Namespace for school-related services
│   │   │   └── add_student_service.rb
│   │   │   └── manage_debt_service.rb
│   │   └── ...
│   ├── decorators # New directory for decorators/presenters
│   │   ├── school_decorator.rb
│   │   └── ...
│   └── views
├── bin
├── config
│   ├── routes.rb # Refactored routes
│   └── ...
├── docs # New directory for high-level documentation (architectural, API, etc.)
│   ├── architecture
│   │   └── overview.md
│   ├── api
│   │   └── v1
│   │       └── users.md
│   │       └── schools.md
│   └── components # Component-level READMEs
│       ├── users
│       │   └── README.md
│       ├── schools
│       │   └── README.md
│       └── ...
├── log # Enhanced logging configuration
└── ...
```

## Refactoring `config/routes.rb`

The `config/routes.rb` file will be significantly refactored to improve readability, maintainability, and separation of concerns. The goal is to make the routes file a clear map of the application's endpoints, without embedding complex logic or excessive nesting. This will also make it easier for junior developers to understand the API surface.

### 1. Route Grouping and Namespacing

We will continue to use `namespace :api do; namespace :v1 do` for API versioning. Within `v1`, routes will be grouped logically by resource. Excessive nesting will be reduced by moving some nested resources to top-level resources with appropriate scoping, or by using custom actions that clearly map to service objects.

### 2. Custom Actions and Member/Collection Routes

Custom `member` and `collection` routes will be used judiciously. For complex operations that involve multiple resources or significant business logic, a dedicated service object will be created, and the route will simply map to a controller action that invokes that service. This keeps the routes file clean and the controller actions thin.

### 3. Separation of Concerns for Authentication/Authorization

Authentication and authorization concerns will be handled at the controller level (e.g., using `before_action` filters) or within policy objects, rather than being reflected in the routes themselves. This keeps the routes focused on resource mapping.

### 4. Example Refactored Routes (Illustrative)

Consider the current `schools` resource with its many nested and custom routes. A refactored version might look like this:

```ruby
# config/routes.rb (Illustrative example of refactored sections)

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # AdminUser Routes
      resources :admin_users, only: [] do
        collection do
          get :schools_for_admin, to: 'admin_users#schools_for_admin'
        end
      end

      # User Routes
      resources :users, only: [:index, :show, :create, :update] do
        member do
          # These actions might invoke UserServices::ManageRolesService, etc.
          patch :add_role
          patch :update_roles
          patch :add_school
        end
        collection do
          get :roles # If roles are a collection related to users
          get :schools # If schools are a collection related to users
        end
      end

      # School Routes
      resources :schools, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :admins
          get :teachers
          get :parents
          get 'parents/:parent_id', to: 'schools#show_parent'
        end
        collection do
          get :search
        end
      end

      # Student Routes (nested under schools, but could be top-level if appropriate)
      resources :schools do
        resources :students, only: [:index, :show, :create, :update, :destroy]
      end

      # Transaction Routes (global and nested)
      resources :transactions, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :process_payment
        end
      end

      resources :schools do
        resources :transactions, only: [:index, :create] do
          collection do
            get :pending
            get :completed
          end
        end
      end

      # Debt Management Routes (can be a top-level resource or nested under schools)
      # If debt management is primarily school-specific, keep it nested.
      # If it's a broader concept, consider a top-level resource.
      resources :debt_management, only: [] do
        collection do
          get :summary
          get :debtors
        end
        member do
          get 'accounts/:account_id', to: 'debt_management#show_account'
          get 'accounts/:account_id/payments', to: 'debt_management#account_payments'
          post 'accounts/:account_id/payments', to: 'debt_management#create_payment'
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
      end

      # Conversation Routes
      resources :conversations, only: [:index, :show, :create] do
        resources :messages, only: [:create, :index]
      end
    end
  end
end
```

This refactoring aims to make the routes more explicit and less deeply nested where possible, relying on the new service objects to handle the underlying complexity. The `users_by_roles` route within `request_accesses` seems misplaced and might be better suited as a custom action on the `users` resource or a dedicated `roles` resource, depending on its exact functionality.

## Adhering to 500-Line Limit

To ensure controllers, models, and other files adhere to the 500-line limit, the following strategies will be employed:

*   **Extract Business Logic to Service Objects:** As mentioned, complex operations will be moved out of controllers and models into dedicated service objects. This is the primary mechanism for reducing file size.
*   **Use Concerns Judiciously:** Rails concerns (`ActiveSupport::Concern`) are useful for sharing common functionality between models or controllers. However, they should be used to encapsulate well-defined, cohesive behaviors, not just to dump unrelated methods. Each concern should ideally be small and focused.
*   **Break Down Large Models:** If a model is growing too large, consider if it's violating the Single Responsibility Principle. Can parts of its functionality be extracted into separate, smaller models, or even into service objects that operate on the model?
*   **Form Objects for Complex Validations:** Move complex validation logic that involves multiple attributes or external dependencies into form objects.
*   **Policy Objects for Authorization:** Centralize authorization logic in policy objects to keep controllers and models focused on their core responsibilities.
*   **Presenter/Decorator for View Logic:** Extract view-specific logic and data formatting into presenter or decorator objects.

By consistently applying these patterns, we can ensure that individual files remain manageable and easy to understand, even for junior developers. This directly supports the NASA standard of restricting functions to a single printed page [1].

## References

[1] The Power of 10: Rules for Developing Safety-Critical Code. Wikipedia. [https://en.wikipedia.org/wiki/The_Power_of_10:_Rules_for_Developing_Safety-Critical_Code](https://en.wikipedia.org/wiki/The_Power_of_10:_Rules_for_Developing_Safety-Critical_Code)


