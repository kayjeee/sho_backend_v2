# SchoolHeadOffice (SHO) API - Phase 7.1

This repository contains the Ruby on Rails API backend for the SchoolHeadOffice (SHO) platform, utilizing Mongoid/MongoDB.

## 🚀 Recent Updates: Real-Time Messaging & Performance

We have recently completed Phase 7.1, transitioning the messaging system from polling to sub-100ms real-time delivery.

### Key Implementation Details

#### 1. Action Cable (WebSockets)
- **Mount Point**: `/cable`
- **Authentication**: WebSocket connections identify users via `user_email` params or `X-User-Email` headers.
- **Channels**: `ConversationChannel` handles scoped streaming for specific chat threads.
- **Broadcasting**: Messages are broadcasted instantly upon save from the `MessagesController`.

#### 2. Performance Optimizations
- **Memoization**: `@current_user` is now memoized within the `Secured` concern, reducing database hits to once per request.
- **N+1 Query Prevention**: The `ConversationsController#index` now uses bulk pre-fetching for participants, ensuring O(1) performance regardless of the number of conversations.

#### 3. API Routing Refactor
- All core resources are now properly namespaced under `api/v1`.
- User lookup is standardized using `auth0_id` as the primary path parameter.

### Documentation
For detailed technical documentation, please refer to:
- `REALTIME_MESSAGING_CHANGES.md` - Technical implementation guide for WebSockets.
- `CHANGELOG_PHASE_7.md` - List of modified files and specific changes.

## 🛠 Setup & Configuration

* **Ruby version**: 8.0.2
* **Database**: MongoDB (via Mongoid)
* **Real-Time**: Redis (configured in `config/cable.yml`)
