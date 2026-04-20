# Technical Audit: Two-Way Communication Feature

## 1. Model Schema & API Contract

### Conversation Model
- **Fields:**
  - `school_id`: `BSON::ObjectId` (Reference to School)
  - `user_id`: `BSON::ObjectId` (Reference to User)
  - `last_message_at`: `DateTime` (Used for sorting)
- **Participants:** Stored as referenced `belongs_to` associations (relational style), not embedded.
- **Next.js Hook:** `GET /api/v1/conversations?school_id=...` or `?user_id=...`

### Message Model
- **Fields:**
  - `content`: `String` (Required)
  - `school_id`: `BSON::ObjectId` (Optional, identifies sender as school)
  - `user_id`: `BSON::ObjectId` (Optional, identifies sender as user)
  - `conversation_id`: `BSON::ObjectId` (Reference to parent Conversation)
  - `name`: `String` (Sender display name)
  - `schoolName`: `String` (Sender school name)
- **Next.js Hook:** `GET /api/v1/conversations/:conversation_id/messages`

---

## 2. Controller Logic Scoping
- **Scoping:** Currently, conversations are scoped by passing `school_id` or `user_id` as query parameters in `ConversationsController#index`.
- **Risk:** There is **no server-side enforcement** of `current_user` ownership. A user could theoretically fetch any conversation by providing another user's ID.
- **Recommended Fix:** Scoping should be derived from the Auth0 token (e.g., `Conversation.where(user_id: @current_user.id)`).

---

## 3. School Directory Logic
- **Mechanism:** Users are retrieved via the `UserSchoolRole` join model.
- **Endpoints:**
  - `GET /api/v1/schools/:id/admins`
  - `GET /api/v1/schools/:id/teachers`
  - `GET /api/v1/schools/:id/parents`
- **Filtering:** Done via `UserSchoolRole.where(school_id: @school.id, role: role)`.

---

## 4. Auth0 Integration
- **Identification:** Handled by the `Secured` concern and `Auth0Client`.
- **Token Decoding:** `ApplicationController#authorize` decodes the Bearer token into `@decoded_token`.
- **Missing Link:** The `current_user` (User model instance) is **not** automatically loaded. Controllers like `UsersController` manually load the user via `load_user_by_auth0!` which extracts `auth0_id` from params, not necessarily the token.

---

## 5. Identified Gaps (Missing Links)
1. **Missing Unified Directory:** No single endpoint to get a grouped list of all school contacts (Admin, Teacher, Parent).
2. **Conversation Security:** Lack of `current_user` scoping in `ConversationsController`.
3. **Real-time:** The models are standard Mongoid documents; ActionCable integration is defined in routes but not fully utilized in the current controller logic for message broadcasting.
4. **Message Sender Logic:** `MessagesController#find_sender` relies on manually passed `user_id`/`school_id` in the request body, which is a security vulnerability.
