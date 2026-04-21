# Project Changes Summary - Email Identification & Conversation Scoping

This document summarizes the technical changes made to transition the SchoolHeadOffice (SHO) platform to email-based identification and to enhance the security and functionality of the Conversations API.

## 1. Authentication & Identification
**File:** `app/controllers/concerns/secured.rb`

- **Removed**: Legacy Auth0 JWT validation logic (local development bypass).
- **Added**: Email-based identification via:
    - `X-User-Email` custom HTTP header.
    - `user_email` request parameter.
- **Security**:
    - Returns `401 Unauthorized` if no email is provided.
    - Returns `401 Unauthorized` if the provided email does not match an existing user record.
    - Sets `@current_user` for all downstream controller actions.

## 2. Data Model Enhancements
**File:** `app/models/conversation.rb`

- **Fields Added**:
    - `participant_ids` (Array, default: `[]`): Stores a list of user IDs (as strings) involved in the conversation.
- **Performance**:
    - Added an index on `participant_ids` to ensure fast lookups.
    - Added indices on `school_id` and `user_id`.

## 3. Conversations API Refactoring
**File:** `app/controllers/api/v1/conversations_controller.rb`

- **Authorization**: Enabled `before_action :authorize` to protect all endpoints.
- **Strict Scoping**:
    - All queries (`index`, `show`, `destroy`) are now scoped to `@current_user.id`.
    - Users can only access conversations where they are the creator (`user_id`) or a participant (`participant_ids`).
- **Create Logic**:
    - Refactored `create` to handle `participant_ids`.
    - Automatically merges the `@current_user.id` into the participant list.
    - Uses `find_or_create_by` on a sorted, unique array of participant IDs to prevent duplicate threads between the same group of users.
- **Rails 8 Syntax**:
    - Replaced direct parameter access with `params.dig(:conversation, :...)`.
    - Standardized `render json:` responses with appropriate HTTP status codes.
- **Error Handling**:
    - Returns `400 Bad Request` if `school_id` is missing during creation.
    - Returns `404 Not Found` if a conversation is missing or if the user does not have access, preventing information leakage.

## Files Involved
1. `app/controllers/concerns/secured.rb`
2. `app/models/conversation.rb`
3. `app/controllers/api/v1/conversations_controller.rb`
4. `DOCS_CHANGES.md` (This file)
