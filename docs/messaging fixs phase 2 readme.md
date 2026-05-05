# Messaging System — Full Fix Summary

Real-time two-way chat built on **Rails Action Cable + MongoDB (Mongoid 9) + Next.js**.  
This document covers every bug found, every fix applied, and the final recommended architecture.

---

## Table of Contents

1. [Problem Overview](#1-problem-overview)
2. [Fix 1 — WebSocket URL (wrong endpoint)](#2-fix-1--websocket-url-wrong-endpoint)
3. [Fix 2 — Mongoid 9 `after_create_commit` crash](#3-fix-2--mongoid-9-after_create_commit-crash)
4. [Fix 3 — SWR polling disabled](#4-fix-3--swr-polling-disabled)
5. [Fix 4 — Stale closure in `sendMessage`](#5-fix-4--stale-closure-in-sendmessage)
6. [Fix 5 — Duplicate message prevention](#6-fix-5--duplicate-message-prevention)
7. [Fix 6 — Typing indicator poll removed](#7-fix-6--typing-indicator-poll-removed)
8. [Fix 7 — Rails MessageSerializer `id` field](#8-fix-7--rails-messageserializer-id-field)
9. [Fix 8 — Action Cable mount + CORS](#9-fix-8--action-cable-mount--cors)
10. [Architecture: How It All Works Together](#10-architecture-how-it-all-works-together)
11. [File Reference](#11-file-reference)
12. [Railway Cost Impact](#12-railway-cost-impact)

---

## 1. Problem Overview

| Symptom | Root cause |
|---|---|
| `WebSocket connection to 'ws://localhost:4000/' failed` | Cable URL missing `/cable` path |
| `500 Internal Server Error` on `/api/v1/conversations` | Mongoid 9 broke `after_create_commit :method` signature |
| Messages re-fetched on every tab focus / reconnect | SWR `revalidateOnFocus` and `refreshInterval` not configured |
| Sent messages occasionally duplicated in the UI | Stale `remoteMessages` closure in `mutate` call |
| Typing indicator making HTTP requests every 10s for nothing | `useSWR` polling a stub that always returns `null` |
| WebSocket broadcast ID mismatch causing dedup to fail | `MessageSerializer` not converting `BSON::ObjectId` to string |
| `Subscription Rejected` after user switch without refresh | Cable consumer singleton not re-initialised when email changes |

---

## 2. Fix 1 — WebSocket URL (wrong endpoint)

**File:** `lib/cable.ts`

**Problem:** The consumer was connecting to `ws://localhost:4000/` (the HTTP root) instead of `ws://localhost:4000/cable`. The URL builder was not stripping `/api/v1` suffixes before appending `/cable`.

**Before:**
```typescript
const consumer = createConsumer(`${process.env.NEXT_PUBLIC_API_URL}?user_email=${email}`);
```

**After:**
```typescript
import { createConsumer, Consumer } from '@rails/actioncable';

let consumer: Consumer | null = null;
let consumerEmail: string | null = null;

export function getCableConsumer(email: string): Consumer {
  if (consumer && consumerEmail === email) return consumer;

  // Disconnect stale consumer if user switched accounts
  if (consumer) {
    consumer.disconnect();
    consumer = null;
  }

  const base = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:4000';

  // Strip /api/v1 suffix, strip trailing slash, swap http→ws
  const wsBase = base
    .replace(/\/api\/v1\/?$/, '')
    .replace(/\/$/, '')
    .replace(/^http/, 'ws');

  const url = `${wsBase}/cable?user_email=${encodeURIComponent(email)}`;
  console.log('[Cable] Connecting to:', url); // → ws://localhost:4000/cable

  consumer = createConsumer(url);
  consumerEmail = email;
  return consumer;
}
```

**Why the identity-aware singleton matters:** If a user logs out and a different user logs in without a full page reload, the old WebSocket stays open under the previous email. The `consumerEmail` check disconnects and recreates the consumer automatically.

---

## 3. Fix 2 — Mongoid 9 `after_create_commit` crash

**File:** `app/models/message.rb`

**Problem:** Mongoid 9 changed the internal signature of `after_create_commit`. Passing a symbol (method name) raises `wrong number of arguments (given 2, expected 1)`. Because this error occurs during class loading, **every request** that touches the `Message` model crashed with a 500 — including `GET /api/v1/conversations`, which eager-loads the model.

**Before:**
```ruby
after_create_commit :broadcast_to_participants

private

def broadcast_to_participants
  MessagesChannel.broadcast_to(conversation, MessageSerializer.new(self).as_json)
end
```

**After:**
```ruby
# Mongoid 9 requires a block — symbol callbacks are broken
after_create do |doc|
  MessagesChannel.broadcast_to(
    doc.conversation,
    MessageSerializer.new(doc).as_json
  )
end
```

**Also fixed — "Overwriting existing field" warnings:**  
These appear when Rails dev-mode reloads the `Message` class and `field` declarations run twice. Ensure each field is declared exactly once in `message.rb` and that no included module or concern re-declares the same fields. Add to suppress during investigation:

```ruby
# config/initializers/mongoid_suppress_warnings.rb
Mongoid.logger.level = Logger::ERROR
```

> **Important:** After making this change, do a full server restart (`rails s`). A hot reload will not clear the cached broken class.

---

## 4. Fix 3 — SWR polling disabled

**File:** `lib/hooks/useMessaging.ts`

**Problem:** SWR defaults (`revalidateOnFocus: true`, `revalidateOnReconnect: true`) were causing REST API hits every time the user switched browser tabs or the network briefly dropped. On Railway, each HTTP request counts against your usage.

**Applied to both `useConversations` and `useMessages`:**
```typescript
{
  revalidateOnFocus: false,      // no re-fetch on tab focus
  revalidateOnReconnect: false,  // no re-fetch on network reconnect
  refreshInterval: 0,            // no polling
  dedupingInterval: 60000,       // cache responses for 60s
}
```

**Result:** REST is called exactly once when the component mounts. All subsequent updates arrive via WebSocket push — zero polling cost.

---

## 5. Fix 4 — Stale closure in `sendMessage`

**File:** `lib/hooks/useMessaging.ts` → `useMessages` hook

**Problem:** After `MessagingAPI.sendMessage` resolved, the code mutated the SWR cache using a snapshot of `remoteMessages` captured at the time `sendMessage` was called:

```typescript
// BUGGY — if a WebSocket message arrived during the await, this drops it
mutate(swrKey, [...remoteMessages, realMessage], false);
```

If a WebSocket broadcast (from another participant) arrived during the `await`, `remoteMessages` was stale and that message was silently lost from the cache.

**After:**
```typescript
// CORRECT — always reads the current cache value at mutation time
mutate(
  swrKey,
  (current: Message[] | undefined) => {
    const existing = current || [];
    // Guard: don't add if already present (e.g. arrived via WebSocket first)
    if (existing.some(m => m.id === realMessage.id)) return existing;
    return [...existing, realMessage];
  },
  false
);
```

---

## 6. Fix 5 — Duplicate message prevention

**Files:** `lib/hooks/useMessaging.ts` → `useConversationSubscription`

**Problem:** Rails broadcasts to **all** subscribers, including the sender. So when user A sends a message:
1. The REST response adds it to the cache via `sendMessage`
2. The WebSocket `received()` callback also receives the broadcast and tries to add it again

Without deduplication, the sender sees the message twice.

**The `received` callback already has the correct guard — verify it is in place:**
```typescript
received(data: Message) {
  const swrKey = `/api/v1/conversations/${conversationId}/messages`;
  mutate(
    swrKey,
    (current: Message[] | undefined) => {
      const messages = current || [];
      // This line is the dedup guard — requires matching `id` fields
      if (messages.some(m => m.id === data.id)) return messages;
      return [...messages, data];
    },
    false
  );
},
```

**This only works if the `id` in the WebSocket payload matches the `id` returned by the REST response.** See Fix 7 below.

---

## 7. Fix 7 — Rails `MessageSerializer` ID field

**File:** `app/serializers/message_serializer.rb`

**Problem:** MongoDB stores IDs as `BSON::ObjectId`. Without explicit serialization, the `id` field may be omitted or serialized as a Ruby object reference rather than a plain string. The frontend's `normalizeMessage` handles `_id.$oid` from REST responses, but the WebSocket broadcast payload goes through a different path — if `id` is blank or malformed there, the deduplication check (`messages.some(m => m.id === data.id)`) always fails and duplicates appear.

```ruby
# app/serializers/message_serializer.rb
class MessageSerializer < ActiveModel::Serializer
  attributes :id, :conversation_id, :sender_id, :content, :created_at, :read, :status

  def id
    object.id.to_s
  end

  def conversation_id
    object.conversation_id.to_s
  end

  def sender_id
    object.sender_id.to_s
  end
end
```

All `BSON::ObjectId` fields are explicitly converted to strings so both the REST response and WebSocket broadcast produce identical `id` values.

---

## 8. Fix 8 — Action Cable mount + CORS

**Files:** `config/routes.rb`, `config/environments/development.rb`, `app/channels/application_cable/connection.rb`

### `config/routes.rb`
```ruby
mount ActionCable.server => '/cable'
```

### `config/environments/development.rb`
```ruby
config.action_cable.mount_path = '/cable'
config.action_cable.allowed_request_origins = [
  'http://localhost:3000',
  'http://127.0.0.1:3000'
]
```

### `app/channels/application_cable/connection.rb`
```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      email = request.params[:user_email]
      user  = User.find_by(email: email)
      user || reject_unauthorized_connection
    end
  end
end
```

### `app/channels/messages_channel.rb`
```ruby
class MessagesChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find(params[:conversation_id])
    stream_for conversation
  end

  def unsubscribed; end
end
```

---

## 9. Fix 6 — Typing indicator poll removed

**File:** `lib/hooks/useMessaging.ts` → `useTyping`

**Problem:** A `useSWR` call with `refreshInterval: 10_000` was firing a real HTTP request every 10 seconds to an endpoint that returned `null`. This wasted Railway compute on every active user.

**Before:**
```typescript
useSWR(swrKey, async () => null, { refreshInterval: 10_000 });
```

**After (temporary placeholder until WebSocket typing is implemented):**
```typescript
// Typing indicators belong on the WebSocket, not REST polling.
// Implement via MessagesChannel#typing action when ready.
const isOtherTyping = false;
```

**Future implementation (WebSocket-based):**
```ruby
# app/channels/messages_channel.rb
def typing(data)
  ActionCable.server.broadcast(
    "conversation_#{params[:conversation_id]}",
    { type: 'typing', user_id: current_user.id.to_s, is_typing: data['is_typing'] }
  )
end
```

---

## 10. Architecture: How It All Works Together

```
User opens conversation
        │
        ▼
REST GET /messages  ──────────────────────►  Rails API
(once, on mount)    ◄──────────────────────  Returns message array
        │
        ▼
WebSocket connects
ws://[host]/cable?user_email=...  ──────────►  Action Cable
        │                         ◄──────────  Handshake confirmed
        │
        ▼
User sends message
        │
        ├─ Optimistic UI update (instant, local state)
        │
        ├─ REST POST /messages  ─────────────►  Rails creates Message
        │                                        after_create broadcasts
        │                                        to MessagesChannel
        │
        ├─ REST response  ◄──────────────────  Confirmed message with real ID
        │  mutate(cache, updater fn)
        │
        └─ WebSocket received()  ◄───────────  Broadcast arrives for all
           dedup check by ID                   subscribers (incl. sender)
           skips if already in cache
```

**Key principle:** REST handles initial load and write acknowledgement. WebSocket handles all real-time delivery. No polling anywhere.

---

## 11. File Reference

| File | Change |
|---|---|
| `lib/cable.ts` | Identity-aware singleton consumer, correct `/cable` URL construction |
| `lib/hooks/useMessaging.ts` | SWR polling disabled, stale closure fixed, typing poll removed |
| `lib/api/messaging-api.ts` | No changes required — `sendMessage` and `normalizeMessage` correct |
| `app/models/message.rb` | `after_create` block replaces broken `after_create_commit :symbol` |
| `app/serializers/message_serializer.rb` | Explicit `id`, `conversation_id`, `sender_id` string conversion |
| `app/channels/messages_channel.rb` | `stream_for conversation` subscription |
| `app/channels/application_cable/connection.rb` | `user_email` param auth, `reject_unauthorized_connection` |
| `config/routes.rb` | `mount ActionCable.server => '/cable'` |
| `config/environments/development.rb` | Cable mount path + CORS origins |
| `config/initializers/mongoid_suppress_warnings.rb` | Suppress duplicate field warnings during dev reload |

---

## 12. Railway Cost Impact

| Before | After |
|---|---|
| SWR polling conversations every ~30s | Zero polling — WebSocket push only |
| SWR refetch on every tab focus | Disabled |
| Typing endpoint polled every 10s per active user | Removed entirely |
| `GET /conversations` crashing with 500 (Mongoid bug) | Fixed — returns 200 |
| WebSocket failing to connect → frontend retrying in a loop | Fixed — single stable connection |

**Net result:** An active user in a chat window now makes exactly 2 HTTP requests on load (conversations list + messages for the open conversation) and 1 per message sent. Everything else is WebSocket frames, which are free on Railway's TCP layer.