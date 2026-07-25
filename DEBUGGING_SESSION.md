# Phase 2: Learner Invitation System Reconciliation & Implementation Report

This document records the exact changes, bug fixes, and feature reconciliations performed during Phase 2. All updates were conducted exclusively on the local development branch (`silence-gem-backtraces-10625524574831857542`), keeping the production branch (`parent-onboarding-complete-step`) untouched and reference-only.

---

## 1. Resolved Boot and Eager Load Crash
*   **The Issue**: `Api::AuthController` skipped authenticity token checks using `skip_before_action :verify_authenticity_token`. However, because it inherits from an API-mode `ApplicationController` (`ActionController::API`), forgery protection callbacks were never registered, throwing an `ArgumentError` on boot/eager loading.
*   **The Fix**: Removed the `skip_before_action :verify_authenticity_token` line from `app/controllers/api/auth_controller.rb` entirely. Zeitwerk check now compiles with 100% success.

---

## 2. Restored Path-Based Backward Compatibility Routing
*   **The Issue**: The Next.js frontend admin onboarding flow actively hits the legacy path-based endpoints:
    *   `GET /api/v1/users/:auth0_id`
    *   `GET /api/v1/users/:auth0_id/schools`
    *   `GET /api/v1/users/:auth0_id/onboarding_status`

    The local branch retained these route mappings in `config/routes.rb` but deleted their action handlers from `UsersController`, causing 404 ActionNotFound crashes.
*   **The Fix**: Implemented a dedicated path-based loading sequence filter (`set_user_by_path`) and restored the action handlers (`show_by_path`, `schools_by_path`, `onboarding_status_by_path`) inside `app/controllers/api/v1/usersController.rb`. These now correctly serialize users, schools, and progress statuses.

---

## 3. Reconciled `CreateUserService` & User Model
*   **The Issue**: The local branch simplified registration logic down to a bare `find_or_initialize_by` call, stripping out valuable multi-provider (Google, Facebook, Twitter, Auth0) mappings and email fallback matching from the stable production branch. It also removed User `phone` and `phone_number` fields.
*   **The Fix**:
    *   Restored `field :phone, type: String` and `field :phone_number, type: String` on `app/models/user.rb` to support SMS/WhatsApp invitation paths.
    *   Merged the production branch's robust `CreateUserService` logic (handling alternative Auth0 prefixes and email-based matching) with the local branch's correct modern BSON error rescues (`BSON::Error::InvalidObjectId`, `Mongoid::Errors::DocumentNotFound`, and `Mongoid::Errors::InvalidFind`).
    *   Refactored dirty-tracking callbacks on `User` to use ActiveModel-compliant `changes['school_ids']` instead of the ActiveRecord-specific `changes_to_save`.
    *   Implemented `full_name` inside `User` (`name.presence || display_name`) to prevent missing-method crashes on serialized invitation sender records.

---

## 4. Reverted Learner Type Definitions to Canonical Integers
*   **The Issue**: The local branch shifted Learner `status` and `gender` fields to String fields ("active", "M"/"F"), posing an extreme type mismatch and database corruption risk on live production MongoDB records that expect canonical Integers.
*   **The Fix**: Reverted both fields to `Integer` fields with a default of `0` in `app/models/learner.rb`, and updated the GENDERS and STATUSES hashes to align with the production specification:
    ```ruby
    GENDERS  = { 'male' => 0, 'female' => 1, 'other' => 2 }.freeze
    STATUSES = { 'active' => 0, 'inactive' => 1, 'graduated' => 2 }.freeze
    ```
    Preserved the local branch's legitimate additions (such as camelCase field mappings via `as:` and new snapshot fields like `schoolName`, `province`, `telEmergency`).

---

## 5. Aligned Invitation Endpoints & Disabled ParamsWrapper Globally
*   **The Issue**: Under Rails API mode, `ActionController::ParamsWrapper` wraps incoming requests inside `params[:invitation]` based on matching model attributes. Since the frontend passes different parameter names (e.g. `phone_number` and `sender`) than the physical database field names (`recipient_phone_number` and `sender_id`), Rails' automatic parameter wrapping silently discarded `phone_number` and `sender` from the wrapped hash. This resulted in false validation errors ("Phone number is required", "Sender is required").
*   **The Fix**:
    *   Added `wrap_parameters false` inside `ApplicationController` (`app/controllers/application_controller.rb`) to disable parameter wrapping globally for all single-object endpoints.
    *   Updated `InvitationsController#create` to bypass the wrapped fallback entirely and unpack request parameters directly using `params.to_unsafe_h`.
*   **Bulk Create**: Integrated `POST /api/v1/invitations/bulk_create` to accept bulk array payloads. Restored the missing `BulkInvitationService` and updated it to dynamically resolve whether the target model class uses `token` or `invitation_token`, and correctly map status types (Integer vs String) and missing validations (`invited_by_id`, `expires_at`, `learner_phone`).
*   **Accept Invitation**: Implemented `POST /api/v1/invitations/verify` (accept) with snake_case parameter mapping `{ token, auth0_id }`, which delegates to the newly built `UserServices::AcceptInvitationService`.
*   **Token Verification**: Aligned `GET /api/v1/invitations/:token/verify_with_details` to return unified detail response hashes, incorporating defensive standardizations to convert `DateTime` and `TimeWithZone` timestamps into `Time` values before subtracting (avoiding the `TypeError: expected numeric` crash when subtracting timestamps on different formats).
*   **Legacy Listing**: Implemented `LearnerInvitationsController` to keep legacy listing (`GET /api/v1/learner_invitations`) fully functional.

---

## 6. Built transactional `AcceptInvitationService`
Following standard engineering conventions, created `UserServices::AcceptInvitationService` which encapsulates:
1.  Resilient token lookup across both unified `Invitation` and legacy `LearnerInvitation`/`TeacherInvitation` models.
2.  Association lookup for parent users and their target learners.
3.  Resilient linking of parent MongoDB `_id` to the Learner's `parent_ids` array, incorporating full dirty-tracking array-duplication (`.dup`) compliance.
4.  Adding the `parent` role and school BSON IDs to the parent user record.
5.  Marking the invitation status as accepted.
6.  Triggering automatic auto-completion of the `link_learner` step in the user's embedded onboarding flow.

---

## 7. Test Verification
Wrote 7 new comprehensive tests under `test/controllers/invitations_controller_test.rb` verifying auth boot checks, path-based fallback routing, unified verification lookups, bulk creations, unnested create requests, and transactional accepting.

All 13 tests in the suite pass with **100% success** (0 failures, 0 errors, 0 skips).
