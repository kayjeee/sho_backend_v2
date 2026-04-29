# Real-Time Messaging & Backend Optimization (Phase 7.1)

This document summarizes the changes made to transition the SchoolHeadOffice (SHO) messaging system from high-latency SWR polling to sub-100ms real-time delivery via Action Cable, along with critical API routing fixes and performance optimizations.

## 🚀 Key Features & Changes

### 1. Action Cable Infrastructure (WebSockets)
We have implemented a full WebSocket-based communication channel to replace the 3–5s SWR polling mechanism.

*   **`app/channels/application_cable/connection.rb`**:
    *   Updated to authenticate WebSocket connections.
    *   Identifies users via the `user_email` parameter or `X-User-Email` header (consistent with the Auth0-bypass security logic used in development).
*   **`app/channels/conversation_channel.rb`**:
    *   New channel created for real-time messaging.
    *   Users subscribe to specific conversation IDs.
    *   Includes authorization logic to ensure only participants (either the creator or listed in `participant_ids`) can stream messages.
*   **`config/cable.yml`**:
    *   Configured for the `redis` adapter in production.
    *   Added a default fallback to `redis://localhost:6379/1` for `REDIS_URL` to prevent application crashes in local development environments where the variable might be missing.

### 2. Message Broadcasting
*   **`app/controllers/api/v1/messages_controller.rb`**:
    *   Modified the `create` action to broadcast newly saved messages immediately.
    *   Implemented `serialize_message` helper to ensure the broadcasted JSON matches the frontend's expected data structure (including `sender_id`, `timestamp`, and `read` status).
    *   Delivery target: Sub-100ms from database save to client delivery.

### 3. API Routing Refactor
Fixed multiple `ActionController::RoutingError` issues and standardized the API layout.

*   **`config/routes.rb`**:
    *   **Action Cable**: Mounted the WebSocket server at `/cable`.
    *   **Namespacing**: Correctly wrapped `users`, `schools`, and `conversations` inside `namespace :api` and `namespace :v1`.
    *   **User Routes**: Standardized on `auth0_id` as the primary lookup parameter for the `users` resource.
    *   **Collection Routes**: Properly defined `me`, `onboarding_status`, and `schools` endpoints.

### 4. Backend Performance Tuning
Drastically reduced database load and response times by optimizing query patterns.

*   **`app/controllers/concerns/secured.rb`**:
    *   Implemented request-level memoization for `@current_user`.
    *   The system now queries the MongoDB `users` collection exactly once per API request, regardless of how many times `current_user` is accessed.
*   **`app/controllers/api/v1/conversations_controller.rb`**:
    *   **N+1 Query Fix**: Refactored the `index` action to pre-fetch all participants for all active conversations in a single bulk query (`User.in(...)`).
    *   Uses an `index_by` hash for O(1) participant lookup during serialization, eliminating the previous N+1 query bottleneck during list retrieval.

## 📂 Summary of Modified Files

| File Path | Status | Description |
| :--- | :--- | :--- |
| `app/channels/application_cable/connection.rb` | Modified | Auth0/Email authentication for WebSockets. |
| `app/channels/conversation_channel.rb` | **NEW** | Subscription and streaming logic for chats. |
| `app/controllers/api/v1/messages_controller.rb` | Modified | Integrated broadcasting and serialization. |
| `app/controllers/api/v1/conversations_controller.rb` | Modified | N+1 performance optimization for indices. |
| `app/controllers/concerns/secured.rb` | Modified | User lookup memoization. |
| `config/routes.rb` | Modified | Mounting /cable and API namespace cleanup. |
| `config/cable.yml` | Modified | Redis adapter configuration and dev safety. |

## 🛠 Next Steps (Frontend)
With the backend ready, the frontend (`useMessaging.ts`) can now:
1.  Connect to `ws://[host]/cable?user_email=[email]`.
2.  Subscribe to `ConversationChannel` with `{ id: conversation_id }`.
3.  Remove SWR `refreshInterval` polling entirely.
4.  Use `mutate` to manually inject incoming WebSocket messages into the local SWR cache.
