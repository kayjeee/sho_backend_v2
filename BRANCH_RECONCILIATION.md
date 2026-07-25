# Branch Reconciliation & Architecture Baseline Report (Phase 1)

This report establishes the baseline architecture, identifies pre-existing structural issues, maps out the authentication/onboarding flows, and provides actionable recommendations to align the production branch (`parent-onboarding-complete-step`) and the local development branch (`silence-gem-backtraces-10625524574831857542`) before launching Phase 2.

No application code or tests have been modified during this phase.

---

## 1. Branch Diff Summary

An exhaustive file-by-file and logical comparison was performed between the stable production branch (`origin/parent-onboarding-complete-step`) and the active local development branch (`silence-gem-backtraces-10625524574831857542`).

### 1.1. Core Architectural Shift: The School Hierarchy
The local development branch introduces a major multi-tier school management hierarchy: **School ➔ Grade ➔ SchoolClass ➔ Learner**.
*   **Production Branch**: Stored learners directly under `Grade` models with standard attributes (like `capacity`, `fees`, `min_age`, `max_age`, `academic_year_start/end`) residing on the `Grade` model itself.
*   **Local Development Branch**: Drastically simplifies the `Grade` model to just 4 fields (`name`, `level`, `description`, `order`). It delegates classroom-specific features (such as `capacity`, `class_teacher_id`, `subject_teacher_ids`, and `learner_ids`) to a brand-new model, **`SchoolClass`**. Learners are assigned directly to a `SchoolClass` within a `Grade`.

---

### 1.2. File-by-File Changes, Source of Errors, and Legitimate Progress

| File Path | Change Status | Type of Change / Detailed Analysis | Legitimate Progress? | Source of Errors? |
| :--- | :--- | :--- | :--- | :--- |
| **`app/controllers/api/auth_controller.rb`** | **NEW** (Local Only) | Defines endpoints `/api/auth/login` and `/api/auth/me`. Contains `skip_before_action :verify_authenticity_token`. | **Partial** (Auth Interceptor placeholder) | **YES (CRITICAL)**: Inherits from `ApplicationController` (`ActionController::API`), which does not include forgery protection. Calling `skip_before_action` on a non-existent callback throws `ArgumentError: Before process_action callback :verify_authenticity_token has not been defined` during Zeitwerk/boot. |
| **`app/models/school_class.rb`** | **NEW** (Local Only) | Introduces the class-tier unit model (e.g. "9A") with `capacity` (default 40), `class_teacher_id`, `subject_teacher_ids` (Hash), and `learner_ids` (Array of ObjectIds). | **YES**: Necessary for the nesting hierarchy. | No |
| **`app/controllers/api/v1/classes_controller.rb`** | **NEW** (Local Only) | Standard CRUD actions for class management and advanced operations like `assign_teacher` and `move_learner`. | **YES**: Exposes the classroom management endpoints. | No |
| **`config/routes.rb`** | **Modified** | Extends routes with the `SchoolClass` endpoints, nested layouts, and fallback routes. Reorganizes block structures into strict `only: [...]` declarations. | **YES**: Aligns routing with the hierarchy. | **YES (CRITICAL)**: Outlines backward-compatibility path routes pointing to `users#show_by_path`, `users#schools_by_path`, and `users#onboarding_status_by_path` which do not exist in the local `UsersController`! |
| **`app/controllers/api/v1/usersController.rb`** | **Modified** | Simplifies user operations but deletes the path-based compatibility methods (`show_by_path`, `schools_by_path`, `onboarding_status_by_path`). Retains fallback query/token decoding logic. | **NO (Regression)**: Deleting actions while keeping their routes caused immediate `AbstractController::ActionNotFound (404)` integration test and production crash failures. | **YES (CRITICAL)**: Deletion of action methods triggers crashes on path-based requests. |
| **`app/services/user_services/create_user_service.rb`** | **Modified** | Production branch contains an extremely mature, robust service supporting pre-fixed `auth0_id` matching, standard provider fallbacks (`google-oauth2`, `facebook`), email fallback finders, and input sanitization. The local branch simplified this to a basic `Struct`-based `find_or_initialize_by` call. | **NO (Regression)**: Slashes the safety and flexibility of the registration system. | No |
| **`app/models/learner.rb`** | **Modified** | production stores `status` and `gender` as **Integers** with scope mappings. Local branch maps these fields directly to camelCase physical DB keys via aliases, introduces new snapshot fields (like `schoolName`, `province`, `telEmergency`), but stores `status` and `gender` as **Strings** ("active", "M", "F"). | **YES** on field-mapping and snapshotting; **NO** on type-change risks. | **YES (RISK)**: Modifying types of load-bearing fields without a data migration or dual-type fallback causes silent validation and retrieval failures on existing production records. |
| **`app/models/grade.rb`** | **Modified** | production uses a feature-heavy model with academic years, fees, and capacities. Local branch strips this down to 4 basic fields, delegating all academic management to `SchoolClass`. | **YES**: Vital structural simplification for hierarchy. | No |
| **`app/models/learner_invitation.rb`** & **`app/models/teacher_invitation.rb`** | **Modified** | production utilizes descriptive models tracking South African phone validations, magic-link helpers, and base64 tokens. Local branch completely rewrites both into simplified, integer-status-based models. | **NO (Regression)**: Simplifies them to the point of breaking legacy phone-based WhatsApp invitations. | No |
| **`app/models/invitation.rb`** | **Identical** | Unified invitation model using `SecureRandom.urlsafe_base64(32)` tokens and magic links. | **YES**: Excellent forward progress for unified invitations. | No |
| **`app/services/user_services/invitation_service.rb`** | **Modified** | production targets `LearnerInvitation` or `TeacherInvitation` based on roles. Local branch targets the new unified `Invitation` model. | **YES**: Aligns with the unified invitation vision. | No |
| **`app/models/user.rb`** | **Modified** | Maps `onboarding_completed` and `onboarding_progress` and includes correct BSON error rescues. Local branch removes `phone` and `phone_number` fields. | **YES** on BSON fixes; **NO** on field deletions. | No |
| **`app/models/school.rb`** | **Modified** | production contains simplified indexes. Local branch configures explicit, named index structures, unique validations on `schoolEmail`, and association overrides. | **YES**: Optimizes school querying. | No |
| **`app/controllers/application_controller.rb`** | **Modified** | Extends unexpected API crash handlers to return clean JSON errors via `BacktraceCleanerUtil`. | **YES**: Essential crash resilience. | No |
| **`app/lib/backtrace_cleaner_util.rb`** | **NEW** (Local Only) | Cleans framework-level noise from error traces. | **YES**: Enhances logger readability. | No |

---

## 2. Known System Constraints (Read-Only)

The backend has inherited or developed a list of load-bearing system constraints that any future code (including Phase 2) must respect:

### 2.1. camelCase Database vs. snake_case Ruby Field Mismatches
*   **The Issue**: MongoDB physical collections contain camelCase keys (e.g. `firstName`, `lastName`, `accessionNumber`, `gradeId`). Standard Mongoid queries against snake_case symbols (like `where(first_name: ...)` or `where(grade_id: ...)`) silently return zero results or crash.
*   **Workaround**: Ensure physical field definitions are mapped exactly using `as:` options:
    ```ruby
    field :firstName, as: :first_name, type: String
    field :accessionNumber, as: :accession_number, type: String
    ```
*   **Association Key Traps**: Associations must explicitly declare `foreign_key` to avoid Mongoid guessing based on the standard class name (which generates BSON object ID casting errors when matched against string keys):
    ```ruby
    belongs_to :grade, class_name: 'Grade', foreign_key: :gradeId
    ```

### 2.2. Resilient Identifier Lookup (Workaround Pattern)
*   **The Issue**: Frontend clients pass BSON ObjectIds, URL-slugs, or hyphenated names as route parameters. Standard `Model.find` fails when passed non-BSON strings.
*   **The Pattern**: `resolve_school_id` resolves context flexibly by converting hyphens back to spaces (`gsub('-', ' ')`) and running regex pattern matching directly via `School.collection.find` (raw collection queries bypass relational type-casting traps):
    ```ruby
    # Raw collection queries are required when querying ID fields stored as Strings
    School.collection.find(
      "$or" => [
        { "schoolName" => name_pattern },
        { "school_name" => name_pattern },
        { "name" => name_pattern }
      ]
    ).first
    ```

### 2.3. BSON::ObjectId::Invalid NameError Crash
*   **The Issue**: Under modern BSON gem versions (BSON v5+) utilized in Rails 8.0.2 / Mongoid 9.0.6, the constant `BSON::ObjectId::Invalid` has been **removed**. Calling/rescuing it throws a `NameError: uninitialized constant BSON::ObjectId::Invalid` instead of intercepting the exception, resulting in 500 errors.
*   **The Rule**: Always catch `BSON::Error::InvalidObjectId`, `Mongoid::Errors::DocumentNotFound`, and `Mongoid::Errors::InvalidFind` instead.

### 2.4. after_create_commit Callback Crash
*   **The Issue**: `after_create_commit` and `after_update_commit` are Active Record-specific callbacks. Mongoid does not natively support transaction commit lifecycle hooks unless explicitly configured with Active Record transactions. Specifying symbol callbacks with `after_create_commit` in a Mongoid model causes unhandled runtime crashes during instantiation.
*   **The Rule**: Restrict callbacks to standard Mongoid hooks like `after_create` or `after_save`.

### 2.5. Mongoid Dirty Tracking on Hashes & Arrays
*   **The Issue**: Editing elements inside a Mongoid `Hash` or `Array` field directly (e.g., `user.onboarding_status.client_metadata["foo"] = "bar"`) does **not** trigger Mongoid's dirty tracking. As a result, saving the parent record silently discards updates.
*   **The Rule**: Always call `.dup` or reassign the field to trigger persistence:
    ```ruby
    meta = (onboarding_status.client_metadata || {}).dup
    meta["step_completed_at"] = Time.current.iso8601
    onboarding_status.client_metadata = meta
    ```

### 2.6. Mongoid Criteria Method Chaining Constraint
*   **The Issue**: Calling `.compact` directly on a `Mongoid::Criteria` object immediately executes the underlying MongoDB query and returns a Ruby `Array`, destroying the ability to chain standard lazy querying methods like `.skip` or `.limit`.
*   **The Rule**: Handle optional parameters by filtering a criteria array and splatting it into `any_of` (e.g., `any_of(*criteria_array.compact)`).

---

## 3. Existing Auth / Onboarding Flow

### 3.1. End-to-End Flow Diagram (Frontend ➔ Backend)

```mermaid
sequenceDiagram
    autonumber
    actor User as Client (Next.js Mobile/Desktop)
    participant Auth0 as Auth0 Provider
    participant R_API as Rails API (Secured)
    participant S_OS as OnboardingStatusService
    participant DB as MongoDB

    User->>Auth0: Visit Home / Login (Check size -> Mobile/Desktop View)
    Auth0-->>User: Returns Access Token + User Claims
    User->>R_API: GET /api/v1/users/me (Bearer Token)
    Note over R_API: Secured concern extracts token sub (Auth0 ID)
    R_API->>DB: Find/Create User by Auth0 ID
    DB-->>R_API: Returns User (Lazy init OnboardingStatus)
    R_API-->>User: Returns User JSON + onboardingStatus data

    rect rgb(240, 248, 255)
        Note over User: Next.js Onboarding Guard checks needsOnboarding flag
        alt Onboarding Incomplete
            User->>User: Redirects to Stepper Onboarding Workflow
            alt Role: Admin
                Note over User: Step 1: AdminSearchPage (Search schools)<br/>Step 2: CreateSchoolForm (No schools found)<br/>Step 3: ValidateSchoolStep<br/>Step 4: ReviewSchoolStep
                User->>R_API: POST /api/v1/users/:id/onboarding_status/complete_step
                R_API->>S_OS: complete_step(user, step_name)
                S_OS->>DB: Updates embedded onboarding_status (duplicating array for dirty tracking)
                DB-->>R_API: Success
                R_API-->>User: Enriched JSON with updated completionPercentage
            else Role: Parent
                Note over User: Steps 1-8: parent_onboarding steps
                User->>R_API: POST /api/v1/users/:id/onboarding_status/complete_step (profile_setup)
            end
        else Onboarding Complete
            User->>User: Allows access to Dashboard / SettingsLayout
        end
    end
```

---

### 3.2. Detailed Onboarding Architecture

#### User Roles Generalization
While the onboarding stepper (Step 1: Search School, Step 2: Create School, Step 3: Validate, Step 4: Review) is primarily utilized by **Admin** users, other user roles (Parents, Teachers, Learners, Principals) share the identical backend onboarding model structure.
Specifically, `OnboardingStatus` tracks progress by defining static arrays for different roles:
*   `ADMIN_STEPS`: `['create_grades', 'upload_learners', 'send_invites', 'admin_onboarding']` (4 steps)
*   `PARENT_STEPS`: `['profile_setup', 'link_learner', 'pay_deposit', 'parent_onboarding']` (8 total steps in transition)
*   `GUEST_STEPS`: `['guest_onboarding']` (1 step)

#### Onboarding Status Location
The onboarding status lives inside an **embedded document** on the `User` model (`embeds_one :onboarding_status`).
To ensure fast querying and filtering of users, the `User` model also exposes **denormalized fields**:
*   `onboarding_completed` (Boolean)
*   `onboarding_progress` (Float)

These fields are synchronized automatically whenever the embedded onboarding document is saved via an `after_save :sync_to_user` callback on the `OnboardingStatus` model:
```ruby
def sync_to_user
  user.set(
    onboarding_completed: all_steps_completed?,
    onboarding_progress: completion_percentage
  )
end
```
*To guarantee embedded lifecycle callbacks fire reliably, you must save the embedded document directly (e.g. `@user.onboarding_status.save!`) instead of relying solely on saving the parent document.*

---

### 3.3. Gap Analysis: Frontend vs. Backend Status Synchronicity

There are three major gaps between the frontend navigation and the current Ruby on Rails source of truth:

1.  **Missing Routing Compatibility**:
    The Next.js frontend performs path-based lookups to fetch status: `/api/v1/users/:auth0_id/onboarding_status`. On the backend, `config/routes.rb` maps this route to `onboarding_status_by_path`. However, the local branch deleted this method from `UsersController`, causing standard frontend requests to fail with a **404 ActionNotFound** crash.
2.  **Lack of Cohesive "Onboarding Guard" enforcement**:
    If a user attempts to bypass the onboarding flow by entering dashboard URLs, the frontend relies on client-side state flags to trigger redirects. The RoR backend does **not** enforce global onboarding interceptors at the API controller layer (such as rejecting non-onboarding requests with `403 Forbidden` if onboarding is incomplete), presenting a security risk.
3.  **Role Synchronization Delay**:
    When a user accepts an invitation in Phase 2, their role changes (e.g., from `guest` to `parent`). The `OnboardingStatus` role step lists are calculated dynamically. If the `roles` field on the parent user model is updated, the embedded `OnboardingStatus` needs to be forcefully re-initialized or synced (`reset!`), otherwise progress metrics will map to incorrect step requirements.

---

### 3.4. Existing Service Pattern: `app/services/user_services/`
The codebase organizes user operations using service objects to keep controllers lean. This established convention must be respected during Phase 2:
*   **Structure**: Services are initialized with parameters and execute their core routine in a `call` method.
*   **Result Pattern**: They return an operational `Result` object containing `success?`, `errors`, and the target payload.
*   **Action Plan for Phase 2**: Any invitation-acceptance business logic (e.g. creating the parent profile, linking learners, updating role fields) must be encapsulated in new service classes under `app/services/user_services/` (such as `UserServices::AcceptInvitationService`) rather than bloated inside controllers.

---

## 4. Recommendations Feeding into Phase 2

Before beginning Phase 2 (Learner Invitation System), the following alignment and reconciliation actions must be carried out:

### 4.1. Reconciled Branch Target State

1.  **Resolve the Zeitwerk / Boot Crash**:
    *   Modify `app/controllers/api/auth_controller.rb` to remove `skip_before_action :verify_authenticity_token` entirely, as API-mode controllers do not register or require request forgery protection.
2.  **Restore Deprecated Path Lookups**:
    *   Either restore `show_by_path`, `schools_by_path`, and `onboarding_status_by_path` methods in `UsersController`, or update `config/routes.rb` to forward these requests directly to the standard actions by converting path tokens to query parameters dynamically.
3.  **Standardize Learner `gender` and `status` Types**:
    *   *Critical Discrepancy*: Production branch expects `Integer` codes for gender/status. Local branch expects `String` codes.
    *   *Solution*: Align models to support both formats dynamically (e.g. map String codes to Integers when writing, or handle dual-type lookups) to prevent data corruption when deployed against existing production records.
4.  **Preserve Legitimate Local Progress**:
    *   Retain the simplified `Grade` model and the nested `SchoolClass` hierarchy.
    *   Retain the clean backtrace logging and BSON error rescues (`BSON::Error::InvalidObjectId`) implemented across controllers.
    *   Retain the unified `Invitation` model.
5.  **Restore Production `CreateUserService`**:
    *   Keep the highly resilient user creation logic from production (which supports alternative Auth0 prefixes and email fallbacks) but update it with the BSON error rescues implemented in local development.

---

### 4.2. Open Questions for Kagiso (Pre-Phase 2)

Before scoping the Phase 2 implementation, please clarify:
1.  **Seeding/Migration**: Are existing parent users in production already seeded with an `onboarding_status` embedded document, or should Phase 2 include an automated backfill/migration task to initialize statuses for older users?
2.  **Invitation Class Deprecation**: Should the legacy `LearnerInvitation` and `TeacherInvitation` models be completely removed in favor of the new unified `Invitation` model, or do we need to maintain backward compatibility with old pending tokens in the database?
3.  **Gender/Status Data Type**: Which data type (Integer vs. String) is the officially approved standard for `Learner`'s status and gender fields going forward?

---

### 4.3. Suggestion for AI Prompt: Frontend (Next.js) CRM Work

If you are running an AI session to implement the frontend features on your CRM branch (`feature/learner-invitation-crm-6860401472260020326`), you can use the following highly detailed system prompt:

```text
You are an expert Next.js frontend engineer assisting with the School Head Office invitations module.
The goal is to implement the Learner Invitation CRM and acceptance flows on the branch `feature/learner-invitation-crm-6860401472260020326` under the repository `https://github.com/kayjeee/SchoolHeadOfffice_invitations`.

Please respect the following constraints and context:
1. Routing: The Next.js client uses Auth0 for authentication. Upon login, the system checks the user's `needsOnboarding` and `onboardingStatus.onboardingCompleted` flags returned by `GET /api/v1/users/me` or `GET /api/v1/users/:auth0_id`.
2. Onboarding Stepper: For Parent accounts, there are up to 8 onboarding steps. The UI should render an OnboardingGuard that redirects incomplete parent setups to `/onboarding` until onboardingCompleted becomes true.
3. API Alignment: Ensure all outgoing network payloads support both snake_case and camelCase parameters (e.g., `school_id` and `schoolId`, `learner_id` and `learnerId`).
4. Invitation Form: Implement a CRM form to send out single or bulk parent invitations. The payload should target `POST /api/v1/invitations` with:
   - `phone_number`: South African format starting with '27' (e.g., 27XXXXXXXXX)
   - `school_id`: MongoDB ObjectId string
   - `grade_id`: MongoDB ObjectId string
   - `role`: "parent"
   - `parent_name`: String
   - `invited_via`: "whatsapp" | "sms"
5. Magic Links: The backend generates magic links with query strings like `?token=abc123xyz&school=Far+North+Secondary`. The frontend must handle this route (e.g., `/parent` or `/onboarding/accept`), extract the query parameters, display the school name, and make an API call to verify the token details via `GET /api/v1/invitations/:token/verify_with_details` or `POST /api/v1/invitations/verify` before prompting the user to sign up.

Please write clean React/Next.js components, hooks for API querying, and route managers. Avoid modifying backend API configuration.
```

---

## 5. Verification Evidence & Dead-Code Assessment

This section compiles exact code-level and diff-level evidence supporting our findings, assesses the status of legacy invitation models, and maps out the real-time API call patterns of the Next.js frontend repository.

### 5.1. Raw Git Diff Evidence for Critical / Risk Findings

#### 5.1.1. `api/auth_controller.rb` — Skip Authenticity Token Callback Crash
The unversioned `AuthController` was newly introduced in the local branch but fails to boot under Rails 8 API mode because `ActionController::API` lacks authenticity token filters:

```ruby
# app/controllers/api/auth_controller.rb
module Api
  class AuthController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:login] # ❌ CRASH: Callback verify_authenticity_token not defined in API-only app.

    def login
      render json: { success: true, message: "Intercepted by Rails Auth Handler" }, status: :ok
    end

    def me
      render json: { success: true, message: "Intercepted by Rails Session Handler" }, status: :ok
    end
  end
end
```

---

#### 5.1.2. `config/routes.rb` Path-Based Routing vs. `UsersController` Action Absence
The local development branch keeps deprecated backward-compatibility path configurations in `config/routes.rb` mapping path lookups to deprecated controller actions:

```ruby
# config/routes.rb (Line 49-61 on local branch)
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
```

However, the local `UsersController` has completely removed these methods, causing standard routing requests to crash with an immediate `AbstractController::ActionNotFound (404)` error.
The original actions on the production branch were:

```ruby
# origin/parent-onboarding-complete-step:app/controllers/api/v1/usersController.rb
before_action :load_user_by_path!, only: [:show_by_path, :schools_by_path, :onboarding_status_by_path]

def show_by_path
  log_deprecated("/api/v1/users/:auth0_id", params[:auth0_id])
  render_success(message: "User retrieved", data: { user: serialize_user(@user) })
end

def schools_by_path
  log_deprecated("/api/v1/users/:auth0_id/schools", params[:auth0_id])
  fetch_schools_for(@user, deprecated_url: "/api/v1/users/schools?auth0_id=xxx")
end

def onboarding_status_by_path
  log_deprecated("/api/v1/users/:auth0_id/onboarding_status", params[:auth0_id])
  # ...
end
```

On the local branch, running a search reveals these actions are **completely absent** from `app/controllers/api/v1/usersController.rb`, confirming this high-stakes bug:
```bash
$ git show silence-gem-backtraces-10625524574831857542:app/controllers/api/v1/usersController.rb | grep "by_path"
# (Returns empty - verified genuinely absent!)
```

---

#### 5.1.3. `learner.rb` — Gender / Status Integer to String Field Mismatches

**Production Branch Field Mappings**:
```ruby
# origin/parent-onboarding-complete-step:app/models/learner.rb (Lines 10-11, 34-35)
field :gender,           type: Integer, default: 0
field :status,           type: Integer, default: 0

GENDERS  = { 'male' => 0, 'female' => 1, 'other' => 2 }.freeze
STATUSES = { 'active' => 0, 'inactive' => 1, 'graduated' => 2 }.freeze
```

**Local Branch Field Mappings**:
```ruby
# silence-gem-backtraces-10625524574831857542:app/models/learner.rb (Lines 14, 24, 46-47)
field :gender,          type: String
field :status,          type: String, default: "active"

GENDERS  = %w[M F Other male female other].freeze
STATUSES = %w[active inactive graduated].freeze
```
*Verification Check:* This mismatch poses an extreme risk. Existing production databases storing integers (e.g. `0` or `1`) will fail string validations or return inconsistent values on the simplified local branch.

---

#### 5.1.4. `user.rb` — Removal of `phone` and `phone_number` Fields on Local Branch

**Production Branch Field Definitions**:
```ruby
# origin/parent-onboarding-complete-step:app/models/user.rb (Lines 17-18)
field :phone,            type: String
field :phone_number,     type: String
```

**Local Branch Field Definitions**:
```bash
$ git show silence-gem-backtraces-10625524574831857542:app/models/user.rb | grep "phone"
# (Returns empty - verified fields have been entirely removed!)
```

---

#### 5.1.5. `create_user_service.rb` — Robust Logic Lost in Simplification
The git diff between the production branch and local branch highlights extensive loss of defensive registrations, multi-provider lookups, and immutability guards:

```diff
--- origin/parent-onboarding-complete-step:app/services/user_services/create_user_service.rb
+++ silence-gem-backtraces-10625524574831857542:app/services/user_services/create_user_service.rb
-    PROVIDERS = %w[google-oauth2 auth0 facebook twitter].freeze
-
-    # ----------------------------
-    # Entry point
-    # ----------------------------
-    def self.call(user_params:)
-      new(user_params).call
-    end
+    Result = Struct.new(:success?, :user, :errors, keyword_init: true)

-    # ----------------------------
-    # Initialize with normalized params
-    # ----------------------------
-    def initialize(user_params)
-      @params = normalize_params(user_params)
-      validate_params!
-      freeze # Ensure immutability after initialization
+    def initialize(user_params:)
+      @user_params = user_params
     end

-    # ----------------------------
-    # Main call
-    # ----------------------------
     def call
-      user = find_user
-      return update_user(user) if user
-
-      create_user
-    rescue => e
-      Rails.logger.error "💥 CreateUserService failed: #{e.message}"
-      Result.failure(e.message)
-    end
+      # 🔑 Check if user already exists → return it
+      user = User.find_or_initialize_by(auth0_id: @user_params[:auth0_id])
+      user.assign_attributes(@user_params)

-    # ----------------------------
-    # Find existing user
-    # ----------------------------
-    def find_user
-      # First try by exact auth0_id
-      find_by_auth0_id || find_by_prefixed_auth0_id || find_by_email
-    end
-
-    def find_by_auth0_id
-      return nil if params[:auth0_id].blank?
-      User.where(auth0_id: params[:auth0_id]).first
-    end
-
-    def find_by_prefixed_auth0_id
-      return nil if params[:auth0_id].blank? || params[:auth0_id].include?('|')
-
-      PROVIDERS.each do |provider|
-        user = User.where(auth0_id: "#{provider}|#{params[:auth0_id]}").first
-        return user if user
-      end
-      nil
-    end
```

---

### 5.2. Dead-Code Check: `LearnerInvitation` / `TeacherInvitation`

A rigorous grep-based analysis of the codebase on **both branches** reveals that **neither legacy model is dead-code**. They have not been fully replaced by the unified `Invitation` model yet, and remain active dependencies.

#### 5.2.1. References on the Local Development Branch
*   **Controllers (`api/v1/invitations_controller.rb`)**: Still queries both models for token validation and verification fallbacks:
    ```ruby
    # app/controllers/api/v1/invitations_controller.rb
    LearnerInvitation.where(token: token, status: 'pending').first ||
    TeacherInvitation.where(token: token, status: 'pending').first
    ```
*   **Services (`grade_services/invite_learner_service.rb` & `invite_teacher_service.rb`)**: Actively instantiates and saves them when sending invitations via email/phone:
    ```ruby
    # app/services/grade_services/invite_learner_service.rb
    invitation = LearnerInvitation.new(learner_email: email, grade_id: grade.id, ...)
    ```
*   **Model Associations (`app/models/user.rb`)**: Still declares active associations referencing both classes:
    ```ruby
    has_many :learner_invitations_sent, class_name: 'LearnerInvitation', inverse_of: :invited_by
    has_many :teacher_invitations_sent, class_name: 'TeacherInvitation', inverse_of: :invited_by
    has_many :teacher_invitations_received, class_name: 'TeacherInvitation', inverse_of: :teacher
    ```

#### 5.2.2. References on the Production Branch
*   Identical references are maintained across controllers and services.
*   The production branch additionally declares nested route and namespace definitions tied directly to `/api/v1/learner_invitations` and `/api/v1/teacher_invitations`.

#### 5.2.3. Safety Verdict
**NO, they are NOT safe to delete.** They are live, load-bearing dependencies. Fully removing them would break legacy token lookups and the existing `InviteLearnerService`/`InviteTeacherService` systems. They must be maintained in coexistence with the new unified `Invitation` model until these services are fully refactored in Phase 2.

---

### 5.3. Frontend Repo: Read-Only Inspection of Current API Calls

Inspection of the Next.js frontend repository (`kayjeee/SchoolHeadOfffice_invitations`, branch `feature/learner-invitation-crm-6860401472260020326`) reveals the exact network calls made against the backend:

#### 5.3.1. User Profile and Authentication Endpoints
The frontend uses a hybrid strategy of path-based lookups and query-parameter lookups:
*   **New Parent Onboarding Profile Fetch**:
    `GET /api/v1/users/show?auth0_id=auth0|xxx`
    Defined in `lib/api/parent-api.ts` and called during parent dashboard loading:
    ```typescript
    apiClient.get(`/users/show?auth0_id=${encodeURIComponent(auth0Id)}`, responseSchema)
    ```
*   **Standard User Show (Legacy Fallback)**:
    `GET /api/v1/users/auth0|xxx`
    Defined in `pages/index.tsx` and context setups:
    ```typescript
    apiClient.get(`/users/${userId}`, UserSchema)
    ```
*   **Update Profile**:
    `PATCH /api/v1/users/update_profile?auth0_id=auth0|xxx`
    Payload structure is **snake_case** (permitted params are strictly filtered).

---

#### 5.3.2. Onboarding Status Endpoints
*   **Retrieve Onboarding Status (Query Style)**:
    `GET /api/v1/users/onboarding_status?auth0_id=auth0|xxx`
    Called by parent onboarding hook (`lib/hooks/useParentOnboarding.ts` line 115).
*   **Retrieve Onboarding Status (Path Style)**:
    `GET /api/v1/users/auth0|xxx/onboarding_status`
    Called by admin onboarding flow (`components/onboarding/onboarding/services/onboardingService.ts` line 34).
*   **Complete Step**:
    `POST /api/v1/users/auth0|xxx/onboarding_status/complete_step`
    Sends a **snake_case** payload body containing `{ step_name: string, metadata: object }`.
*   **Skip Step**:
    `POST /api/v1/users/auth0|xxx/onboarding_status/skip_step`
    Sends `{ step_name: string, reason: string }`.

*Verification Gap Finding:* This proves the **"Missing Routing Compatibility" gap is 100% active and critical**. The Admin Onboarding flow in Next.js relies directly on path-based endpoints like `/api/v1/users/auth0|xxx/onboarding_status` which crash with a 404 in local development due to the missing actions in `UsersController`.

---

#### 5.3.3. Invitation & Acceptance Endpoints
The frontend already has a heavily configured API client and CRM modules targeting invitation management:
*   **Verify Invitation Token**:
    Tries a fallback sequence of endpoints inside `InvitationAPI.verifyToken` (`lib/api/invitation-api.ts`), specifically starting with:
    1.  `GET /api/v1/invitations/:token/verify_with_details` (Unified backend endpoint)
    2.  `GET /api/v1/invitations/verify?token=:token`
    3.  `GET /api/v1/learner_invitations/verify?token=:token` (Legacy fallback)
*   **Accept Invitation**:
    `POST /api/v1/invitations/verify`
    Sends a **snake_case** body: `{ token: string, auth0_id: string }`.
*   **Send Bulk Invitations**:
    `POST /api/v1/invitations/bulk_create`
    Sends a payload containing `{ invitations: Array<{ phone_number: string, parent_name: string, grade_id: string }> }` inside `lib/services/invitationService.ts`.
*   **Manage/List Invitations**:
    `GET /api/v1/learner_invitations` (Lists pending invitations under the school CRM page).

---

### 5.4. Raw Frontend Evidence Verification & Phase 2 Alignment Confirmation

This sub-section provides raw command-line evidence extracted directly from the checked-out frontend Next.js repository (`kayjeee/SchoolHeadOfffice_invitations` on branch `feature/learner-invitation-crm-6860401472260020326`), confirming the validity of the call inventory.

#### 5.4.1. Verification of `bulk_create` in `invitationService.ts`
Running a raw file inspection verifies the `POST /api/v1/invitations/bulk_create` call and its exact payload:

```bash
$ grep -rn "bulk_create" lib/services/invitationService.ts
51:      const response = await fetch(`${this.invitationsURL}/bulk_create`, {
```

```typescript
// lib/services/invitationService.ts (Lines 40-75)
    const payload = {
      invitations: validInvitations,
      school_id,
      sender_id,
      sender: userEmail,
      role: 'parent',
      invited_via: invitedVia || 'whatsapp',
      country_code: countryCode,
    };

    try {
      const response = await fetch(`${this.invitationsURL}/bulk_create`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-User-Email': userEmail || 'system@schoolheadoffice.com',
        },
        body: JSON.stringify(payload),
      });

      const data = await response.json();

      if (!response.ok || !data.success) {
        throw new Error(data.message || 'Bulk invitation failed');
      }

      return data;
    } catch (error) {
      console.error('Error creating bulk invitations', error);
      throw error;
    }
```

---

#### 5.4.2. Verification of `verify_with_details` in `invitation-api.ts`
Running a raw file inspection verifies the token lookup fallbacks inside `verifyToken`:

```bash
$ grep -n "verify_with_details" lib/api/invitation-api.ts
60:      `/invitations/${token}/verify_with_details`,
```

```typescript
// lib/api/invitation-api.ts (Lines 55-83)
  static async verifyToken(token: string): Promise<InvitationData> {
    console.log(`🔍 [InvitationAPI.verifyToken] Triggered for token: ${token.substring(0, 10)}...`);

    const endpoints = [
      `/invitations/${token}/verify_with_details`,
      `/invitations/verify?token=${token}`,
      `/invitations/${token}`,
      `/teacher_invitations/${token}`,
      `/teacher_invitations/verify?token=${token}`,
      `/invitations/verify_teacher?token=${token}`,
      `/learner_invitations/verify?token=${token}`,
      `/invitations/${token}/verify`
    ];

    let lastError: any = null;

    for (const endpoint of endpoints) {
      try {
        console.log(`📡 [InvitationAPI.verifyToken] Trying endpoint: ${endpoint}`);
        const response = await apiClient.get(endpoint, VerifyWithDetailsSchema);

        // Handle both wrapped and unwrapped response formats
        const invitation = response.data?.invitation || response.invitation;
```

---

#### 5.4.3. Phase 2 Scope & Target Branch Confirmation
We explicitly acknowledge and confirm the following constraints for Phase 2:
1.  **Target Branch Only**: All development, reconciliation, and integration work in Phase 2 will happen **exclusively on the local development branch `silence-gem-backtraces-10625524574831857542`**.
2.  **Production is Off-Limits**: The production branch `parent-onboarding-complete-step` is strictly off-limits. It will **not be touched, modified, or merged into** during Phase 2. It serves as a read-only reference to compare behavior.
3.  **Model Coexistence**: In alignment with the dead-code analysis in Section 5.2, legacy models `LearnerInvitation` and `TeacherInvitation` will be **kept intact** alongside the new unified `Invitation` model. No legacy model files will be deleted or broken during Phase 2 to ensure backward-compatibility with pending tokens and existing service integrations.

---

### 5.5. Verified POST /api/v1/invitations Key Mismatch & Resolution

This sub-section documents the newly found parameter mismatch, the fix applied to reconcile it, and un-nested payloads used for invitation creation.

#### 5.5.1. The Mismatch (Frontend Key vs. Backend Key)
*   **The Bug**: Standard requests to `POST /api/v1/invitations` failed with `"Phone number is required", "Sender is required"` errors even though both parameters were present in the payload body.
*   **Root Cause**:
    1.  **Sender Lookup**: The frontend sends the Auth0 ID under the key `"sender"` directly at the root payload (e.g. `"sender": "auth0|..."`). However, the backend was only checking the key `"sender_id"`.
    2.  **Parameters Unpacking**: The controller did not call `.to_unsafe_h` on the Rails `ActionController::Parameters` object. In Rails 8, iterating or doing deep mappings on raw parameter structures directly without explicitly transforming them to unsafe hashes caused unpermitted or raw properties to be silently filtered out or ignored.

#### 5.5.2. Raw Frontend Call Evidence
The plain single-invitation creation originates from `lib/services/SmsService.ts` and `WhatsAppBusinessService.ts`:

```typescript
// lib/services/SmsService.ts (Lines 74-84)
      const payload = {
        phone_number: phoneNumber,
        school_id: schoolId,
        learner_numbers: learnerNumbers ?? [],
        role: 'parent',
        parent_name: parentName ?? null,
        grade_id: gradeId ?? null,
        invited_via: 'sms',
        sender,
      };
```

#### 5.5.3. Raw Backend Permitted Params & Code
```ruby
# app/controllers/api/v1/invitations_controller.rb
  def create
    Rails.logger.info "📥 [InvitationsController] Creating invitation"

    # Extract, normalize, and validate parameters
    raw_params = params[:invitation] || params
    raw_hash = raw_params.respond_to?(:to_unsafe_h) ? raw_params.to_unsafe_h : raw_params.to_h
    service_params = normalize_hash_keys(raw_hash)

    # Accept both sender_id (backend standard) and sender (NextJS client contract)
    sender = find_sender(service_params[:sender_id] || service_params[:sender])

    # Build service parameters
    service_params = build_service_params(service_params, sender)
    ...
```

---

#### 5.5.4. Additional Un-Inventoried Invitation Endpoints
A broader search of the frontend codebase turned up another invitation path:
*   **Email Invitation creation**:
    Located in `components/onboarding/onboarding/OnboardingFlow/Step3SendInvites/components/ChannelSelection/services/EmailService.ts` (Line 59), this endpoint also targets `POST /api/v1/invitations` but passes `email` instead of `phone_number`:
    ```typescript
    // EmailService.ts
    const payload = {
      email: email,
      school_id: schoolId,
      role: 'parent',
    };
    ```
    *This endpoint is currently reported as an un-inventoried contract variant to be noted for potential future support.*
