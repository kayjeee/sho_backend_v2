# Changelog: Real-Time Messaging & Backend Infrastructure

This document provides a comprehensive overview of all changes implemented to support real-time communication and backend performance optimizations.

## 🚀 New Features

### Real-Time Messaging (WebSockets)
- **Action Cable Integration**: Replaced SWR polling with a WebSocket-based messaging system for sub-100ms delivery.
- **Connection Authentication**: Implemented email-based authentication in `ApplicationCable::Connection` to secure WebSocket handshakes.
- **Conversation Streaming**: Created `ConversationChannel` to allow users to subscribe to live updates for specific chat threads.
- **Automated Broadcasting**: Updated `MessagesController` to broadcast new messages to participants immediately upon creation.

## 🛠 Backend Optimizations

### Performance Tuning
- **Memoization**: Updated the `Secured` concern to memoize the `@current_user` object, reducing MongoDB queries to a single hit per request.
- **N+1 Query Resolution**: Refactored `ConversationsController#index` to pre-fetch all participants for all active conversations in a single bulk query, drastically improving list retrieval speed.

### Infrastructure & Config
- **Redis Support**: Updated `config/cable.yml` for production Redis scaling with a safe fallback for local development.
- **Routing Overhaul**:
    - Mounted the Action Cable server at `/cable`.
    - Corrected API namespacing for `users`, `schools`, and `conversations`.
    - Standardized path-based user lookups using `auth0_id`.

## 📂 Files Created or Modified

| File | Status | Description |
| :--- | :--- | :--- |
| `app/channels/conversation_channel.rb` | **NEW** | Handles WebSocket subscriptions for chats. |
| `REALTIME_MESSAGING_CHANGES.md` | **NEW** | Detailed technical implementation guide. |
| `CHANGELOG_PHASE_7.md` | **NEW** | This changelog file. |
| `app/channels/application_cable/connection.rb` | Modified | WebSocket connection authentication. |
| `app/controllers/api/v1/messages_controller.rb` | Modified | Added broadcast triggers and serialization. |
| `app/controllers/api/v1/conversations_controller.rb` | Modified | Implemented participant pre-fetching. |
| `app/controllers/concerns/secured.rb` | Modified | Implemented `@current_user` memoization. |
| `config/routes.rb` | Modified | Mounted /cable and fixed API namespaces. |
| `config/cable.yml` | Modified | Configured Redis and environment fallbacks. |
