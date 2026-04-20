# Technical Audit: Phase 1 - Rails "Glue" Improvements

## Models Modified & Roles

### 1. User (`app/models/user.rb`)
- **Role:** Central identity provider.
- **Usage:** Now automatically loaded in every secured request via the `Auth0 sub` claim.
- **Key Fields:** `auth0_id`, `name`, `email`, `roles`.

### 2. Conversation (`app/models/conversation.rb`)
- **Role:** Manages the two-way communication channel between a school and a user.
- **Usage:** Scoped strictly to the `@current_user` in the `ConversationsController`.
- **Key Fields:** `school_id`, `user_id`.

### 3. School (`app/models/school.rb`)
- **Role:** The educational institution entity.
- **Usage:** Provides the context for the unified directory.
- **Key Fields:** `schoolName`, `slug`, `logo`.

---

## Controllers & Concerns Modified

### 1. Secured Concern (`app/controllers/concerns/secured.rb`)
- **Action:** Updated `authorize` method.
- **Effect:** Automatically sets `@current_user = User.find_by(auth0_id: sub)` after successful token validation.
- **Benefit:** Ensures all downstream controllers have access to the authenticated User object without manual lookups.

### 2. ConversationsController (`app/controllers/api/v1/conversations_controller.rb`)
- **Action:** Secured `index` and `set_conversation` methods.
- **Effect:** Removed reliance on query parameters for identifying the user. Conversations are now strictly filtered by `@current_user.id`.
- **Benefit:** Prevents unauthorized access to conversations between other users and schools.

### 3. SchoolsController (`app/controllers/api/v1/schools_controller.rb`)
- **Action:** Added `directory` endpoint.
- **Effect:** Returns a unified object containing `admins`, `teachers`, and `parents` for a specific school.
- **Benefit:** Reduces API round-trips for the frontend when building the school contact list.

---

## API Contract Updates

### Scoped Conversations
`GET /api/v1/conversations`
- **Scoping:** Derived from Bearer Token.
- **Response:** List of conversations belonging to the authenticated user.

### Unified Directory
`GET /api/v1/schools/:id/directory`
- **Response:**
  ```json
  {
    "success": true,
    "data": {
      "admins": [...],
      "teachers": [...],
      "parents": [...]
    }
  }
  ```
