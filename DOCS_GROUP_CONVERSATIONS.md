# Group Conversations & Participant Management (Backend)

This document summarizes the changes implemented to support N-participant group conversations, optional group naming, and robust member management in the Rails 7 API using Mongoid/MongoDB.

## 1. Model Changes

### `Conversation` Model (`app/models/conversation.rb`)
- **New Fields:**
  - `group_name` (String, optional): Stores the explicit name of a group chat.
  - `participants_key` (String): A sorted, comma-separated string of participant IDs used for robust set-based uniqueness enforcement in MongoDB.
- **Validations:**
  - `must_have_at_least_one_participant`: Ensures the conversation has members while supporting "Note to Self" (1 participant) and Groups (2+ participants).
- **Callbacks:**
  - `normalise_participant_ids`: Now also maintains the `participants_key` automatically.
- **Indexing:**
  - Migrated from a multi-key array index to a string-based index on `{ participants_key, school_id, group_name }`. This avoids MongoDB indexing limitations and supports multiple distinct named groups with the same participants.

### `Message` Model (`app/models/message.rb`)
- **ID Type Change:** Switched `sender_id`, `user_id`, `school_id`, and added `receiver_id` to use `String` instead of `BSON::ObjectId`. This ensures consistent comparison with frontend IDs and safe storage in MongoDB.
- **Associations Restored:**
  - `belongs_to :sender`, `belongs_to :receiver`, `belongs_to :school`, `belongs_to :conversation`.
  - Corrected `inverse_of` and foreign key mappings to ensure data integrity across `User` and `School` models.

---

## 2. Controller Logic (`app/controllers/api/v1/conversations_controller.rb`)

### Smart Creation (`create` action)
- **1-on-1 Chats:** Automatically looks up existing unnamed conversations between the same two users in the same school using `participants_key` and `school_id`.
- **Group Chats:** Always creates a fresh conversation if a `group_name` is provided or if there are 3+ participants.

### Member Management (`participants` action)
- **GET `/api/v1/conversations/:id/participants`**: Returns a serialized list of all members in the conversation.
- **PUT `/api/v1/conversations/:id/participants`**: Updates the member list.
  - Accepts `participant_ids` (either direct or nested under `conversation`).
  - Performs existence check for all provided User IDs.
  - Returns detailed `errors.full_messages` on validation failure (422).

### Intelligent Titles (`conversation_title` helper)
- Priority:
  1. `group_name` (if present).
  2. "Note to self" (if only 1 participant).
  3. "Full Name" (if 1 other participant).
  4. "First1, First2, and First3" (if 2-3 others, using Rails `to_sentence`).
  5. "First1, First2, and N others" (if 4+ others).

---

## 3. Routing (`config/routes.rb`)

Added member routes to the `conversations` resource:
```ruby
resources :conversations do
  member do
    put :read
    get :participants
    put :participants
  end
end
```

---

## 4. Data Migration & Scripts

### Scripts Provided:
- `script/backfill_participants_key.rb`: Populates the `participants_key` field for existing conversations to enable the new indexing strategy.
- `script/migrate_messages_to_string_ids.rb`: Converts foreign keys in the `messages` collection from `BSON::ObjectId` to `String`.
- `script/drop_unique_index.rb`: Helper to drop the legacy unique index if it exists in the database.

---

## 5. API Usage Examples

### Create a Named Group
```bash
POST /api/v1/conversations
{
  "conversation": {
    "school_id": "SCHOOL_ID",
    "group_name": "Project Alpha",
    "participant_ids": ["USER_ID_1", "USER_ID_2", "USER_ID_3"]
  }
}
```

### Update Participants
```bash
PUT /api/v1/conversations/CONV_ID/participants
{
  "participant_ids": ["USER_ID_1", "USER_ID_4"]
}
```
*(Replaces the current list with the new set of IDs)*
