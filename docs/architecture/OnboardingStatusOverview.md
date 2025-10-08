# Overview of Ruby on Rails Application Changes for Onboarding Status System

This document provides a concise overview of the modifications and additions made to the Ruby on Rails application to support the new onboarding status system. The changes span the model, service, and controller layers, along with new API routes, to enable comprehensive tracking and management of user onboarding progress.

## 1. New API Routes

The following routes have been added to `config/routes.rb` to expose the onboarding status API endpoints. These routes are nested under `/api/v1/users/:user_id` to ensure that onboarding status operations are always tied to a specific user.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :users, only: [] do
        resource :onboarding_status, only: [:show, :update], controller: 'onboarding_status' do
          post :complete_step
          post :skip_step
          post :complete
          post :reset
          get :next_step
          get :analytics
          post :sync
        end
      end
    end
  end
end
```

**Reasoning for Route Structure:**
- **`namespace :api do; namespace :v1 do`**: Standard API versioning to ensure future compatibility and clear separation of API concerns.
- **`resources :users, only: [] do ... end`**: The `users` resource is kept empty (`only: []`) because user creation and management are typically handled by an external authentication provider (e.g., Auth0). The `onboarding_status` resource is nested under `users` to indicate that it operates on a specific user's onboarding data.
- **`resource :onboarding_status, only: [:show, :update], controller: 'onboarding_status'`**: Defines a singular resource for `onboarding_status`. A singular resource is appropriate because each user has only one onboarding status. `show` is for retrieving the status, and `update` is for general updates to the status fields.
- **`post :complete_step`, `post :skip_step`, `post :complete`, `post :reset`, `get :next_step`, `get :analytics`, `post :sync`**: These are custom member routes added to the `onboarding_status` resource. They provide specific actions for managing the onboarding flow:
    - `complete_step`: Marks a specific onboarding step as completed.
    - `skip_step`: Marks a specific onboarding step as skipped.
    - `complete`: Forcefully marks the entire onboarding process as completed.
    - `reset`: Resets the user's onboarding status to its initial state.
    - `next_step`: Retrieves information about the next recommended onboarding step.
    - `analytics`: Provides detailed analytics about the user's onboarding progress.
    - `sync`: Synchronizes the onboarding status with existing user data (e.g., if grades or learners were added outside the onboarding flow).

This structure provides a clear, RESTful interface for interacting with the onboarding status system, allowing the Next.js frontend to manage user progress effectively.

## 2. Model Layer Changes

### 2.1. `OnboardingStatus` Model (New)

A new embedded document model, `OnboardingStatus`, has been introduced to track the progress of a user's onboarding journey. This model is embedded within the `User` model, leveraging MongoDB's document-oriented nature for efficient data storage and retrieval.

**Key Fields and Purpose:**
- `create_grades`, `upload_learners`, `send_invites`: Boolean flags to track the completion of core onboarding steps.
- `admin_onboarding_completed`, `parent_onboarding_completed`, `guest_onboarding_completed`: Boolean flags for role-specific onboarding completion, allowing for tailored onboarding paths.
- `completed`: Overall status indicating if the entire onboarding process is finished.
- `last_updated`, `started_at`, `completed_at`: Timestamps for tracking the lifecycle of the onboarding process.
- `current_step`: Stores the current step the user is on, facilitating navigation and progress display.
- `skipped_steps`: An array to record any steps the user chose to skip, along with reasons.
- `steps_completed_count`, `total_steps_count`, `completion_percentage`: Metrics for quantitative progress tracking.
- `version`, `last_sync_at`, `client_metadata`: Metadata fields for tracking model versioning, last synchronization, and additional client-side context.

**Key Methods and Functionality:**
- `auto_complete_if_ready!`: Automatically marks onboarding as complete when all required steps are finished.
- `next_step`: Determines the next logical step in the onboarding flow based on current progress and user roles.
- `complete_step!`: Marks a specific step as completed, handling dependencies and updating progress metrics.
- `skip_step!`: Records a skipped step and its reason, allowing the flow to continue.
- `reset!`: Resets the onboarding status to its initial state, useful for re-onboarding or testing.
- `to_api_hash`: Serializes the model data into a camelCase format suitable for the Next.js frontend.
- `assign_attributes_from_api`: Deserializes camelCase input from the frontend into snake_case attributes.

**Reasoning:**
Embedding `OnboardingStatus` within the `User` model simplifies data management and ensures atomicity for user-related operations. The detailed fields provide granular control over tracking progress, while the methods encapsulate complex business logic, making the model robust and reusable.

### 2.2. `User` Model Modifications

The existing `User` model has been enhanced to include the `OnboardingStatus` embedded document and provide convenience methods for interacting with the onboarding system.

**Key Additions:**
- `embeds_one :onboarding_status`: Establishes the one-to-one relationship with the `OnboardingStatus` embedded document.
- `after_initialize :ensure_onboarding_status` and `after_create :initialize_onboarding_status`: Ensures that every user has an associated `OnboardingStatus` record, initializing it for new users.
- `update_onboarding_status!`: A wrapper method to update the embedded `onboarding_status` document.
- `needs_onboarding?`, `onboarding_progress`, `current_onboarding_step`: Convenience methods to quickly query the user's onboarding state.
- `complete_onboarding_step!`, `skip_onboarding_step!`, `reset_onboarding!`: Methods to delegate actions to the embedded `onboarding_status` document, providing a consistent interface at the `User` level.
- `can_access_main_features?`: Determines if a user, even if not fully onboarded, has completed enough critical steps to access core application features.
- `onboarding_analytics`: Provides a consolidated hash of onboarding-related analytics for the user.
- `to_api_hash`: Modified to include the `onboardingStatus` data in the API response, ensuring the frontend receives comprehensive user information.
- Class methods like `self.bulk_update_onboarding_status`, `self.by_onboarding_status`, `self.onboarding_statistics`: Added for administrative and analytical purposes, allowing for bulk operations and reporting on user onboarding.

**Reasoning:**
Modifying the `User` model centralizes onboarding logic, making it easy to access and manage a user's onboarding state directly from the `User` object. The added methods simplify interactions and provide a clear API for other parts of the application to query and update onboarding progress.

## 3. Service Layer Changes

### 3.1. `OnboardingStatusService` (New)

A new service class, `UserServices::OnboardingStatusService`, has been introduced to encapsulate the business logic related to onboarding status management. This service acts as an intermediary between the controller and the models, ensuring that complex operations are handled consistently and securely.

**Key Methods and Functionality:**
- `get_status`: Retrieves the current onboarding status for a user, enriching it with contextual data.
- `update_status`: Handles general updates to the onboarding status, including validation and change tracking.
- `complete_step`: Orchestrates the completion of a specific onboarding step, including validation, side effects, and error handling.
- `skip_step`: Manages the skipping of an onboarding step, recording reasons and updating the status.
- `complete_onboarding`: Forcefully completes the entire onboarding process, handling finalization and side effects.
- `reset_onboarding`: Resets a user's onboarding status, with audit trail logging.
- Private helper methods for validation (`validate_updates`, `validate_step_completion`, `validate_role_specific_step`, etc.), context gathering, and side effect handling (`handle_step_side_effects`, `handle_onboarding_completion_side_effects`).

**Reasoning:**
The `OnboardingStatusService` adheres to the 


Single Responsibility Principle, separating business logic from controllers and models. This improves maintainability, testability, and reusability of the onboarding logic. It also centralizes error handling and logging for all onboarding-related operations.

## 4. Controller Layer Changes

### 4.1. `OnboardingStatusController` (New)

A new API controller, `Api::V1::OnboardingStatusController`, has been created to expose the onboarding status functionality via RESTful endpoints. This controller acts as the entry point for frontend requests related to onboarding.

**Key Actions and Functionality:**
- `show`: Handles `GET /api/v1/users/:user_id/onboarding_status` to retrieve a user's onboarding status.
- `update`: Handles `PATCH /api/v1/users/:user_id/onboarding_status` for general updates to the onboarding status.
- `complete_step`: Handles `POST /api/v1/users/:user_id/onboarding_status/complete_step` to mark a specific step as completed.
- `skip_step`: Handles `POST /api/v1/users/:user_id/onboarding_status/skip_step` to mark a specific step as skipped.
- `complete`: Handles `POST /api/v1/users/:user_id/onboarding_status/complete` to force complete onboarding.
- `reset`: Handles `POST /api/v1/users/:user_id/onboarding_status/reset` to reset onboarding status.
- `next_step`: Handles `GET /api/v1/users/:user_id/onboarding_status/next_step` to get the next recommended step.
- `analytics`: Handles `GET /api/v1/users/:user_id/onboarding_status/analytics` to retrieve onboarding analytics.
- `sync`: Handles `POST /api/v1/users/:user_id/onboarding_status/sync` to synchronize onboarding status with user data.

**Key Features:**
- **`before_action :authenticate_user!`**: Ensures that only authenticated users can access these endpoints.
- **`before_action :set_target_user`**: Identifies the user whose onboarding status is being managed, supporting both `auth0_id` and MongoDB `_id`.
- **`before_action :authorize_onboarding_access!`**: Implements authorization logic to ensure that the current user has permission to view or modify the target user's onboarding status (e.g., users can manage their own, admins can manage others).
- **`before_action :set_request_context`**: Gathers contextual information about the request (e.g., user agent, IP address) for logging and auditing.
- **`before_action :check_rate_limit`**: Basic rate limiting to prevent abuse of the API endpoints.
- **`around_action :log_request_performance` and `after_action :track_api_usage`**: For performance monitoring and API usage analytics.
- **Strong Parameter Handling**: Uses `onboarding_params` to permit only allowed parameters, preventing mass assignment vulnerabilities.
- **Error Handling**: Returns appropriate HTTP status codes and detailed error messages for various scenarios (e.g., `404 Not Found`, `422 Unprocessable Entity`, `403 Forbidden`, `400 Bad Request`).

**Reasoning:**
This controller provides a secure and well-defined interface for the frontend to interact with the onboarding system. By leveraging `before_action` filters, it centralizes authentication, authorization, and common request processing logic. The use of a dedicated service layer (`OnboardingStatusService`) keeps the controller lean and focused on handling HTTP requests and responses, adhering to the 


Fat Model, Skinny Controller` principle.

### 4.2. `OnboardingAuthorization` Concern (New)

A new Rails concern, `OnboardingAuthorization`, has been created to encapsulate the authorization logic for accessing and modifying onboarding status. This concern is included in the `OnboardingStatusController`.

**Key Methods and Functionality:**
- `authorize_onboarding_access!`: Checks if the `current_user` has permission to view the `@target_user`'s onboarding status. Permissions are based on:
    - User accessing their own status.
    - `super_admin` role having full access.
    - `admin` role having access to users within their shared schools.
    - `teacher` role having read-only access to users within their shared schools.
- `authorize_onboarding_modification!`: Checks if the `current_user` has permission to modify the `@target_user`'s onboarding status. This is a stricter check, typically allowing only the user themselves, `super_admin`, or `admin` roles with shared schools.

**Reasoning:**
Extracting authorization logic into a concern promotes reusability and keeps the controller clean. It centralizes access control rules, making them easier to manage, test, and update. This ensures that sensitive onboarding data is protected and only accessible to authorized personnel.

## 5. Onboarding Status Flow and Relationships (Mermaid Diagram)

The following Mermaid diagram illustrates the relationships between the key components of the onboarding status system and the flow of data and actions.

```mermaid
graph TD
    subgraph Frontend (Next.js Application)
        A[User Login] --> B{OnboardingGuard}
        B -- Needs Onboarding --> C[OnboardingFlow Component]
        C -- Step Completion --> D[Onboarding API Calls]
        D -- Success/Failure --> C
        B -- Onboarding Complete --> E[Dashboard/Main App]
        E -- Check Status --> D
    end

    subgraph Backend (Ruby on Rails API)
        D --> F[OnboardingStatusController]
        F -- Authenticate & Authorize --> G[OnboardingStatusService]
        G -- Business Logic & Validation --> H[User Model]
        H -- Embeds --> I[OnboardingStatus Model]
        I -- Data Storage --> J[MongoDB]
    end

    subgraph Data Flow
        K[User Data] --> H
        L[Auth0 ID] --> H
        M[Onboarding Status Data] --> I
    end

    subgraph Key Relationships
        H -- has_one --> I
        F -- uses --> G
        G -- interacts_with --> H
        G -- interacts_with --> I
    end

    style A fill:#f9f,stroke:#333,stroke-width:2px
    style B fill:#bbf,stroke:#333,stroke-width:2px
    style C fill:#ccf,stroke:#333,stroke-width:2px
    style D fill:#dfd,stroke:#333,stroke-width:2px
    style E fill:#fcf,stroke:#333,stroke-width:2px
    style F fill:#f9f,stroke:#333,stroke-width:2px
    style G fill:#bbf,stroke:#333,stroke-width:2px
    style H fill:#ccf,stroke:#333,stroke-width:2px
    style I fill:#dfd,stroke:#333,stroke-width:2px
    style J fill:#fcf,stroke:#333,stroke-width:2px
    style K fill:#eee,stroke:#333,stroke-width:1px
    style L fill:#eee,stroke:#333,stroke-width:1px
    style M fill:#eee,stroke:#333,stroke-width:1px
```

**Diagram Explanation:**

- **Frontend (Next.js Application)**:
    - **User Login**: The entry point for users.
    - **OnboardingGuard**: A critical component that checks if a user needs to complete onboarding. If so, it redirects them to the `OnboardingFlow Component`.
    - **OnboardingFlow Component**: The main UI for the onboarding process, guiding the user through various steps.
    - **Onboarding API Calls**: The frontend communicates with the backend via API calls to update and retrieve onboarding status.
    - **Dashboard/Main App**: The primary application interface, accessible once onboarding is complete or if the user has sufficient access.

- **Backend (Ruby on Rails API)**:
    - **OnboardingStatusController**: Receives API requests from the frontend, handles authentication and authorization.
    - **OnboardingStatusService**: Contains the core business logic for managing onboarding status, including validation and side effects.
    - **User Model**: The central model representing a user, which `embeds` the `OnboardingStatus Model`.
    - **OnboardingStatus Model**: The embedded document that stores the detailed progress of the user's onboarding.
    - **MongoDB**: The database where all user and onboarding status data is persistently stored.

- **Data Flow**: Illustrates the movement of data, such as `User Data`, `Auth0 ID`, and `Onboarding Status Data`, between components.

- **Key Relationships**: Highlights the structural and functional relationships between the backend components, such as `User` having an `OnboardingStatus`, and the `Controller` using the `Service`, which in turn interacts with the `Models`.

This diagram provides a high-level visual representation of how the different parts of the system interact to manage the user onboarding process. It emphasizes the separation of concerns and the flow of control and data within the application.

