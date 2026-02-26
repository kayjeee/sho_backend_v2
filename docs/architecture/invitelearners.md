# Learner Invitation API — Overview

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Models Used](#models-used)
3. [Routes & Endpoints](#routes--endpoints)
4. [Service Layer](#service-layer)
5. [Request & Response Examples](#request--response-examples)
6. [Testing Guide (cURL)](#testing-guide-curl)
7. [Error Reference](#error-reference)
8. [Flow Diagrams](#flow-diagrams)

---

## Architecture Overview

The learner invitation system uses **three separate invitation models** (polymorphic-style), a **service object** (`GradeServices::InviteLearnerService`) for business logic, and a unified controller (`Api::V1::InvitationsController`) for token verification and acceptance.

```
Client
  │
  ├─► POST /api/v1/grades/:id/invite_learner        ← Creates the invitation
  │         └── GradeServices::InviteLearnerService
  │                   └── LearnerInvitation (model)
  │
  ├─► GET  /api/v1/invitations/:token/verify_with_details  ← Check before accepting
  │
  ├─► POST /api/v1/invitations/verify               ← Accept the invitation
  │
  └─► GET/POST /api/v1/learner_invitations/*        ← CRUD & lifecycle actions
```

---

## Models Used

### Primary Model: `LearnerInvitation`

Used by the grade-level invite flow and the `InvitationsController` token lookup.

| Field | Type | Description |
|---|---|---|
| `token` | String | Unique urlsafe_base64 token (32 bytes) |
| `status` | String | `pending` / `accepted` / `declined` / `expired` / `cancelled` |
| `role` | String | `parent` or `teacher` (default: `parent`) |
| `recipient_phone_number` | String | Normalized phone (no spaces) |
| `phone_number` | String | Raw phone input |
| `parent_name` | String | Name of the parent being invited |
| `school_id` | String | School identifier |
| `grade_id` | String | Grade identifier |
| `learner_number` | String | Single learner accession number |
| `learner_numbers` | Array | Multiple learner accession numbers |
| `learner_ids` | Array | Internal Learner `_id` references |
| `invited_via` | String | `whatsapp` / `sms` / `email` (default: `whatsapp`) |
| `invited_at` | Time | Set on creation |
| `accepted_at` | Time | Set when accepted |
| `expired_at` | Time | Default: 7 days from creation |
| `cancelled_at` | Time | Set when cancelled |

**Validations:**
- `token` — presence, uniqueness
- `status` — must be in valid set
- `role` — must be `parent` or `teacher`
- `recipient_phone_number` — presence required
- `school_id` — presence required
- At least one of `learner_number`, `learner_numbers`, or `learner_ids` must be present
- `expired_at` must be in the future on create

---

### Secondary Model: `Invitation`

Used by the general `POST /api/v1/invitations` endpoint and `UserServices::InvitationService`. Has stricter South African phone validation (`27XXXXXXXXX` format).

| Key difference vs LearnerInvitation | Detail |
|---|---|
| Phone format | Must match `/\A27\d{9}\z/` exactly |
| Expiration field | `expires_at` (not `expired_at`) |
| `expired?` method | Checks `expires_at <= Time.current` |
| Magic link | Built via `Invitation.build_magic_link` |

> **Note:** The `InvitationsController#find_invitation_by_token` searches **all three models** (`Invitation`, `LearnerInvitation`, `TeacherInvitation`) in order. The first match wins. For learner invite flows, `LearnerInvitation` is the expected match.

---

## Routes & Endpoints

### 1. Create a Learner Invitation (via Grade)

```
POST /api/v1/grades/:id/invite_learner
```

Handled by `GradesController#invite_learner`, delegates to `GradeServices::InviteLearnerService`. Creates a `LearnerInvitation` record.

---

### 2. Create a General Invitation

```
POST /api/v1/invitations
```

Handled by `Api::V1::InvitationsController#create`, delegates to `UserServices::InvitationService`. Creates an `Invitation` record.

---

### 3. Verify Token + Get Details (before accepting)

```
GET /api/v1/invitations/:token/verify_with_details
```

or via the global route:

```
GET /invitations/:token/verify_with_details
```

Public endpoint (no auth). Rate limited. Searches all invitation models.

---

### 4. Accept an Invitation

```
POST /api/v1/invitations/verify
```

Body: `{ token: "...", auth0_id: "..." }`

Accepts the invitation, links the parent to learners, updates User record.

---

### 5. Bulk Create Invitations

```
POST /api/v1/invitations/bulk_create
```

Delegates to `UserServices::BulkInvitationService`.

---

### 6. LearnerInvitation Lifecycle Actions

```
GET    /api/v1/learner_invitations              # index
POST   /api/v1/learner_invitations              # create
GET    /api/v1/learner_invitations/:id          # show
PUT    /api/v1/learner_invitations/:id          # update
DELETE /api/v1/learner_invitations/:id          # destroy

POST   /api/v1/learner_invitations/:id/accept
POST   /api/v1/learner_invitations/:id/decline
POST   /api/v1/learner_invitations/:id/cancel
POST   /api/v1/learner_invitations/:id/resend

GET    /api/v1/learner_invitations/pending
GET    /api/v1/learner_invitations/expired
GET    /api/v1/learner_invitations/by_grade/:grade_id
```

---

## Service Layer

### `GradeServices::InviteLearnerService`

**Location:** `app/services/grade_services/invite_learner_service.rb`

**Constructor:**
```ruby
GradeServices::InviteLearnerService.new(
  grade:             grade,           # Grade record (required)
  invitation_params: params_hash,     # Hash of invitation fields
  user:              current_user     # User record (optional — skips permission check if nil)
)
```

**Returns:** `ServiceResult` Struct with:
- `success` — Boolean
- `errors` — Array of error strings
- `invitation` — The created `LearnerInvitation` record (on success)

**Validation steps:**
1. Permission check — user must have `Admin` or `Teacher` role for the school (skipped if `user` is nil)
2. `grade.can_enroll_learner?` — grade must be active and not at capacity
3. Duplicate check on `learner_email` (pending invitations for same grade)
4. Duplicate check on `learner_phone` (pending invitations for same grade)

---

## Request & Response Examples

### Create via Grade

**Request:**
```http
POST /api/v1/grades/64abc123/invite_learner
Content-Type: application/json

{
  "learner_phone": "27821234567",
  "learner_email": "parent@example.com",
  "parent_name": "Jane Doe",
  "learner_number": "LRN001",
  "invited_via": "whatsapp"
}
```

**Success Response (201):**
```json
{
  "success": true,
  "message": "Invitation sent successfully.",
  "invitation": {
    "id": "64abc456",
    "token": "xK3mP9...",
    "status": "pending",
    "role": "parent",
    "recipient_phone_number": "27821234567",
    "school_id": "64school1",
    "grade_id": "64abc123",
    "learner_number": "LRN001",
    "invited_at": "2026-02-22T10:00:00Z",
    "expired_at": "2026-03-01T10:00:00Z",
    "full_magic_link": "https://www.schoolheadoffice.com/parent?token=xK3mP9...&school=My%20School"
  }
}
```

**Error Response (422):**
```json
{
  "success": false,
  "errors": ["An invitation is already pending for this phone number"],
  "message": "An invitation is already pending for this phone number"
}
```

---

### Verify Token (GET)

**Request:**
```http
GET /api/v1/invitations/xK3mP9.../verify_with_details
```

**Success Response (200):**
```json
{
  "success": true,
  "invitation": {
    "id": "64abc456",
    "token": "xK3mP9...",
    "status": "pending",
    "school_name": "Greenwood Primary",
    "parent_name": "Jane Doe",
    "expired_at": "2026-03-01T10:00:00Z",
    "expired": false,
    "active": true,
    "expires_in_days": 7,
    "full_magic_link": "https://www.schoolheadoffice.com/parent?token=xK3mP9...&school=Greenwood%20Primary"
  },
  "expires_in": 604800,
  "is_expired": false
}
```

**Expired / Not Found:**
```json
{ "success": false, "message": "Invalid or expired invitation link." }
```

---

### Accept Invitation (POST)

**Request:**
```http
POST /api/v1/invitations/verify
Content-Type: application/json

{
  "token": "xK3mP9...",
  "auth0_id": "google-oauth2|123456789"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Invitation accepted successfully",
  "learners": [
    { "id": "64learner1", "accessionNumber": "LRN001" }
  ],
  "invitation": { "id": "64abc456", "status": "accepted", "accepted_at": "2026-02-22T11:00:00Z" }
}
```

---

## Testing Guide (cURL)

Replace `BASE_URL`, `GRADE_ID`, `TOKEN`, and `AUTH0_ID` with real values.

```bash
BASE_URL="http://localhost:3000/api/v1"
GRADE_ID="64abc123"
TOKEN="xK3mP9..."
AUTH0_ID="google-oauth2|123456789"

# 1. Create a learner invitation via grade
curl -X POST "$BASE_URL/grades/$GRADE_ID/invite_learner" \
  -H "Content-Type: application/json" \
  -d '{
    "learner_phone": "27821234567",
    "parent_name": "Jane Doe",
    "learner_number": "LRN001",
    "invited_via": "whatsapp"
  }'

# 2. Verify token before accepting
curl "$BASE_URL/invitations/$TOKEN/verify_with_details"

# 3. Accept the invitation
curl -X POST "$BASE_URL/invitations/verify" \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$TOKEN\", \"auth0_id\": \"$AUTH0_ID\"}"

# 4. List pending learner invitations for a grade
curl "$BASE_URL/learner_invitations/by_grade/$GRADE_ID"

# 5. Cancel an invitation
curl -X POST "$BASE_URL/learner_invitations/64abc456/cancel"

# 6. Resend an invitation
curl -X POST "$BASE_URL/learner_invitations/64abc456/resend"

# 7. Create via general invitations endpoint
curl -X POST "$BASE_URL/invitations" \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "27821234567",
    "school_id": "64school1",
    "learner_number": "LRN001",
    "parent_name": "Jane Doe",
    "role": "parent",
    "invited_via": "whatsapp",
    "sender_id": "'"$AUTH0_ID"'"
  }'
```

---

## Error Reference

| HTTP Status | Scenario |
|---|---|
| 200 | Success (verify, accept) |
| 201 | Created (invitation created) |
| 207 Multi-Status | Bulk create — partial success |
| 404 Not Found | Token not found in any model |
| 409 Conflict | Invitation already accepted/expired |
| 410 Gone | Invitation expired |
| 422 Unprocessable | Validation failed, duplicate, missing params |
| 500 Internal Server Error | Unexpected exception |

---

## Flow Diagrams

### Invitation Creation Flow

```
Admin/Teacher
     │
     ▼
POST /grades/:id/invite_learner
     │
     ▼
GradesController#invite_learner
     │
     ▼
GradeServices::InviteLearnerService
     ├── validate_permissions (skipped if user nil)
     ├── grade.can_enroll_learner?
     ├── duplicate phone/email check
     └── LearnerInvitation.save
              │
              ▼
         token generated (SecureRandom.urlsafe_base64 32)
         expired_at = 7.days.from_now
         status = 'pending'
              │
              ▼
    Return { success: true, invitation: ... }
```

### Invitation Acceptance Flow

```
Parent (has magic link token)
     │
     ▼
GET /invitations/:token/verify_with_details
     │
     ├── find in Invitation → LearnerInvitation → TeacherInvitation
     ├── check expired? and pending?
     └── return details + expires_in

     (Parent completes signup/login with Auth0)
     │
     ▼
POST /invitations/verify  { token, auth0_id }
     │
     ├── find invitation by token
     ├── validate not expired, pending
     ├── find learners by learner_ids → learner_numbers → phone fallback
     ├── learner.add_parent(auth0_id)  for each learner
     ├── user.school_ids |= [school_id]
     └── invitation.update!(status: 'accepted', accepted_at: Time.current)
```

---

## Key Implementation Notes

**Token lookup order** in `find_invitation_by_token`: The controller checks `Invitation` first (with `status: pending`), then `LearnerInvitation`, then `TeacherInvitation`. If a `LearnerInvitation` token matches an older `Invitation` token (collision), the `Invitation` record would win. This is unlikely given `urlsafe_base64(32)` entropy but worth knowing.

**Expiration field naming inconsistency**: `LearnerInvitation` uses `expired_at`; `Invitation` uses `expires_at`. The controller's `extract_expiration_date` handles both via `respond_to?` checks.

**Phone normalization**: `LearnerInvitation` strips whitespace only. `Invitation` validates strict `27XXXXXXXXX` format and fails validation otherwise. Make sure phone numbers are pre-normalized before calling the general invitations endpoint.

**`user: nil` in service**: Passing `user: nil` to `InviteLearnerService` **skips all permission checks**. Only do this from trusted internal contexts (e.g. admin scripts, seeds). Controller calls should always pass the authenticated user.