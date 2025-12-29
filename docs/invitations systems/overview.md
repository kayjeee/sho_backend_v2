# 📨 Invitations System - Overview

## 📋 Table of Contents
- [Introduction](#introduction)
- [System Architecture](#system-architecture)
- [Core Components](#core-components)
- [Data Flow](#data-flow)
- [API Endpoints](#api-endpoints)
- [Common Use Cases](#common-use-cases)
- [Security Model](#security-model)
- [Error Handling](#error-handling)
- [Performance Considerations](#performance-considerations)

---

## 🎯 Introduction

The **Invitations System** is a robust solution for connecting parents to their children's school data. It allows school staff (teachers/admins) to send secure, token-based invitations to parents via multiple channels (WhatsApp, SMS, Email).

### Key Features
- ✅ **Single & Multiple Learner Support** - Invite parents to one or many learners in one invitation
- ✅ **Token-Based Security** - Unique, secure tokens with expiration
- ✅ **Robust Learner Lookup** - Multi-strategy search with fallback mechanisms
- ✅ **Phone Normalization** - Automatic handling of South African phone formats
- ✅ **Auto-Linking** - Automatic parent-learner relationship creation
- ✅ **Legacy Data Support** - Works with inconsistent historical data
- ✅ **Public API** - No authentication required for invitation acceptance

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      CLIENT APPLICATION                      │
│  (Mobile App / Web Portal / WhatsApp Bot / SMS Gateway)     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   API GATEWAY LAYER                          │
│                                                              │
│  POST /api/v1/invitations          ← Create Invitation      │
│  GET  /invitations/:token/verify   ← Verify Token           │
│  POST /api/v1/invitations/verify   ← Accept Invitation      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   BUSINESS LOGIC LAYER                       │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         InvitationService (Core Logic)               │  │
│  │  • Validate Input                                     │  │
│  │  • Find School & Learners                            │  │
│  │  • Create Invitation Record                          │  │
│  │  • Auto-link Relationships                           │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │    InvitationsController (HTTP Interface)            │  │
│  │  • Request Validation                                 │  │
│  │  • Response Formatting                               │  │
│  │  • Error Handling                                     │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      DATA LAYER (MongoDB)                    │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ Invitations │  │  Learners   │  │   Schools   │        │
│  │  Collection │  │  Collection │  │  Collection │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                              │
│  ┌─────────────┐                                            │
│  │    Users    │                                            │
│  │  Collection │                                            │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧩 Core Components

### 1. **Invitation Model** (`app/models/invitation.rb`)
The central data model representing an invitation.

**Key Fields:**
- `token` - Unique secure token
- `status` - pending | accepted | expired | rejected
- `recipient_phone_number` - Parent's phone
- `learner_ids` - Array of learner ObjectIds
- `learner_numbers` - Array of accession numbers
- `learner_names` - Array of learner full names
- `expires_at` - Expiration timestamp (default: 7 days)

**Key Methods:**
- `valid_invitation?` - Check if still usable
- `accept!` - Mark as accepted
- `expire!` - Mark as expired
- `to_api_hash` - Serialize for API response

### 2. **InvitationService** (`app/services/user_services/invitation_service.rb`)
Core business logic for invitation creation.

**Responsibilities:**
- Validate sender and school
- Find learners with robust multi-strategy lookup
- Create invitation record
- Auto-link parent to learners
- Comprehensive logging

**Key Methods:**
- `call` - Main entry point
- `find_learners!` - Multi-strategy learner search
- `find_learner_by_any_field` - Single learner lookup with fallbacks
- `auto_link_parent!` - Create parent-learner relationships

### 3. **InvitationsController** (`app/controllers/api/v1/invitations_controller.rb`)
HTTP interface for invitation operations.

**Endpoints:**
- `verify_with_details` - GET invitation details
- `create` - POST new invitation
- `verify` - POST accept invitation

**Responsibilities:**
- Request validation
- Service orchestration
- Response formatting
- Error handling

---

## 🔄 Data Flow

### Creating an Invitation

```
┌─────────┐
│ Client  │
└────┬────┘
     │
     │ POST /api/v1/invitations
     │ {sender_id, phone_number, school_id, learner_number(s)}
     ▼
┌─────────────────────────┐
│ InvitationsController   │
│  • Validate sender      │
│  • Extract parameters   │
└────┬────────────────────┘
     │
     │ Initialize InvitationService
     ▼
┌─────────────────────────────────────────────────────┐
│ InvitationService                                    │
│                                                      │
│  1. Find School by ID                               │
│     ↓                                                │
│  2. Find Learners (Multi-Strategy)                  │
│     ├─ Clean Mongoid query (ObjectId + String)     │
│     └─ Raw Mongo fallback (legacy support)         │
│     ↓                                                │
│  3. Create Invitation Record                        │
│     • Generate unique token                         │
│     • Set expiration (7 days)                       │
│     • Store learner IDs, numbers, names             │
│     ↓                                                │
│  4. Auto-link Parent to Learners                    │
│     • Add sender auth0_id to learner.parent_auth0_ids │
│     • Idempotent (skip if already linked)           │
│     ↓                                                │
│  5. Return Created Invitation                       │
└────┬────────────────────────────────────────────────┘
     │
     │ Return invitation object
     ▼
┌─────────────────────────┐
│ InvitationsController   │
│  • Format response      │
│  • Return 201 Created   │
└────┬────────────────────┘
     │
     │ 201 Created
     │ {success: true, invitation: {...}}
     ▼
┌─────────┐
│ Client  │
└─────────┘
```

### Accepting an Invitation

```
┌─────────┐
│ Client  │
└────┬────┘
     │
     │ 1. GET /invitations/:token/verify_with_details
     ▼
┌──────────────────────────────────────────────┐
│ InvitationsController#verify_with_details    │
│  • Find invitation by token                  │
│  • Check status = 'pending'                  │
│  • Return invitation details                 │
└────┬─────────────────────────────────────────┘
     │
     │ 200 OK {invitation details}
     ▼
┌─────────┐
│ Client  │ (User reviews invitation)
└────┬────┘
     │
     │ 2. POST /api/v1/invitations/verify
     │    {token, auth0_id}
     ▼
┌──────────────────────────────────────────────────────────┐
│ InvitationsController#verify                             │
│                                                          │
│  1. Find invitation by token                            │
│     ↓                                                    │
│  2. Find learners (3-step fallback)                     │
│     ├─ By stored learner_ids (primary)                  │
│     ├─ By accession numbers (secondary)                 │
│     └─ By phone numbers (tertiary)                      │
│     ↓                                                    │
│  3. Link parent to learners                             │
│     • Call learner.add_parent(auth0_id)                 │
│     ↓                                                    │
│  4. Update user profile                                 │
│     • Add school_id to user.school_ids                  │
│     • Update phone_number if missing                    │
│     • Update invited_via if missing                     │
│     ↓                                                    │
│  5. Mark invitation as accepted                         │
│     • Set status = 'accepted'                           │
│     • Set accepted_at timestamp                         │
└────┬─────────────────────────────────────────────────────┘
     │
     │ 200 OK {success: true, learners: [...]}
     ▼
┌─────────┐
│ Client  │
└─────────┘
```

---

## 🔌 API Endpoints

### 1. Verify Invitation Details (Public)
```http
GET /invitations/:token/verify_with_details
```

**Purpose:** Check invitation validity and retrieve details before acceptance.

**Response:**
```json
{
  "success": true,
  "invitation": {
    "id": "676c1234567890abcdef1234",
    "token": "abc123def456",
    "recipient_phone_number": "27831234567",
    "role": "parent",
    "status": "pending",
    "school_id": "676a1234567890abcdef5678",
    "school_name": "Example High School",
    "learner_ids": ["676b1234567890abcdef9012"],
    "learner_names": ["John Smith"],
    "learner_count": 1,
    "expires_at": "2025-01-05T10:30:00Z",
    "expired": false,
    "valid": true
  }
}
```

### 2. Create Invitation (Public)
```http
POST /api/v1/invitations
Content-Type: application/json

{
  "sender_id": "auth0|teacher123",
  "phone_number": "27831234567",
  "school_id": "676a1234567890abcdef5678",
  "learner_number": "LRN2024001",
  "parent_name": "Jane Doe",
  "role": "parent",
  "invited_via": "whatsapp"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Invitation sent successfully.",
  "invitation": {
    "id": "676c1234567890abcdef1234",
    "token": "abc123def456",
    "recipient_phone_number": "27831234567",
    "learner_ids": ["676b1234567890abcdef9012"],
    "learner_names": ["Student Name"],
    "expires_at": "2025-01-05T10:30:00Z"
  }
}
```

**Multiple Learners:**
```json
{
  "sender_id": "auth0|teacher123",
  "phone_number": "27831234567",
  "school_id": "676a1234567890abcdef5678",
  "learner_numbers": ["LRN2024001", "LRN2024002"],
  "parent_name": "Jane Doe",
  "invited_via": "whatsapp"
}
```

### 3. Accept Invitation (Public)
```http
POST /api/v1/invitations/verify
Content-Type: application/json

{
  "token": "abc123def456",
  "auth0_id": "auth0|parent123"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Invitation accepted successfully",
  "learners": [
    {
      "id": "676b1234567890abcdef9012",
      "firstName": "John",
      "lastName": "Smith",
      "accessionNumber": "LRN2024001",
      "school_id": "676a1234567890abcdef5678"
    }
  ]
}
```

---

## 💼 Common Use Cases

### Use Case 1: Single Learner Invitation
**Scenario:** A teacher invites a parent to view one child's data.

```javascript
// Step 1: Create invitation
const response = await fetch('/api/v1/invitations', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    sender_id: 'auth0|teacher123',
    phone_number: '27831234567',
    school_id: '676a1234567890abcdef5678',
    learner_number: 'LRN2024001',
    parent_name: 'Jane Doe',
    invited_via: 'whatsapp'
  })
});

const { invitation } = await response.json();
// invitation.token → Send via WhatsApp/SMS

// Step 2: Parent verifies invitation
const details = await fetch(
  `/invitations/${invitation.token}/verify_with_details`
);

// Step 3: Parent accepts
await fetch('/api/v1/invitations/verify', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    token: invitation.token,
    auth0_id: 'auth0|parent123'
  })
});
```

### Use Case 2: Multiple Learners (Siblings)
**Scenario:** A parent has 3 children at the same school.

```javascript
const response = await fetch('/api/v1/invitations', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    sender_id: 'auth0|admin456',
    phone_number: '27831234567',
    school_id: '676a1234567890abcdef5678',
    learner_numbers: ['LRN2024001', 'LRN2024002', 'LRN2024003'],
    parent_name: 'Sarah Johnson',
    invited_via: 'email'
  })
});

// Single invitation links parent to all 3 learners
```

### Use Case 3: WhatsApp Bot Integration
**Scenario:** Automated invitation via WhatsApp bot.

```javascript
// When user sends "REGISTER LRN2024001" via WhatsApp
async function handleWhatsAppRegistration(phoneNumber, learnerNumber) {
  const response = await fetch('/api/v1/invitations', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sender_id: 'system|whatsapp-bot',
      phone_number: phoneNumber,
      school_id: getSchoolIdFromContext(),
      learner_number: learnerNumber,
      invited_via: 'whatsapp'
    })
  });
  
  const { invitation } = await response.json();
  
  // Send WhatsApp message with link
  await sendWhatsAppMessage(phoneNumber, 
    `Click here to complete registration: 
     https://app.school.com/invite/${invitation.token}`
  );
}
```

---

## 🔐 Security Model

### Token Security
- **Unique Tokens:** SecureRandom.hex(10) - 20 characters
- **Collision Prevention:** Loop until unique token found
- **Expiration:** 7 days default (configurable)
- **Single Use:** Status changes to 'accepted' after use

### Access Control
- **Public Endpoints:** No authentication required
- **Explicit Context:** All actions require explicit IDs (sender_id, auth0_id)
- **School Context:** Learners validated against school_id
- **Role Validation:** Role field validated against allowed values

### Data Protection
- **Phone Normalization:** Automatic format standardization
- **Input Validation:** Required fields enforced
- **SQL Injection:** Mongoid ORM protection
- **XSS Protection:** Rails built-in sanitization

---

## ⚠️ Error Handling

### Common Errors

| Error | Status | Cause | Solution |
|-------|--------|-------|----------|
| `Sender not found` | 422 | Invalid sender_id | Verify Auth0 user exists |
| `School not found: {id}` | 422 | Invalid school_id | Check school ObjectId |
| `Learner not found: {number}` | 422 | No matching learner | Verify accession number |
| `Missing learner_number(s)` | 422 | Empty learner data | Provide learner_number or learner_numbers |
| `Invalid or expired invitation` | 404 | Token invalid/expired | Create new invitation |
| `Missing auth0_id` | 422 | No auth0_id provided | Include parent auth0_id |

### Error Response Format
```json
{
  "success": false,
  "errors": ["Detailed error message here"]
}
```

### Logging
All operations are comprehensively logged:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📨 [InvitationService] START
🏫 school_id=676a1234567890abcdef5678
👨‍👩‍👧 learner_numbers=["LRN2024001"]
📞 phone=27831234567
🔎 [InvitationService] Searching learners (robust mode)
   ↳ ✅ matched learner 676b... accession=LRN2024001
✅ [InvitationService] CREATED invitation_id=676c...
   ↳ token=abc123def456
   ↳ learners=676b1234567890abcdef9012
```

---

## ⚡ Performance Considerations

### Database Queries
- **Indexed Fields:** token, status, school_id, learner_ids
- **Query Optimization:** Uses `where(:id.in => [...])` for bulk lookups
- **Fallback Strategy:** Primary query → Fallback query (only if needed)

### Caching Opportunities
- School lookups (rarely change)
- User lookups (for sender validation)
- Invitation details (for verification endpoint)

### Scalability
- **Stateless Design:** No session dependencies
- **Async Processing:** Invitation sending can be queued
- **Batch Operations:** Supports multiple learners per invitation
- **Connection Pooling:** MongoDB connection pool configured

---

## 📊 Monitoring & Observability

### Key Metrics to Track
- Invitation creation rate
- Acceptance rate (conversions)
- Average time to acceptance
- Expiration rate
- Lookup fallback frequency (indicates data quality)

### Health Checks
```ruby
# Check system health
GET /api/v1/invitations/health

# Response
{
  "status": "healthy",
  "pending_invitations": 1234,
  "accepted_today": 45,
  "acceptance_rate": 0.82
}
```

---

## 🔄 Backward Compatibility

The system maintains full compatibility with:

✅ **Single learner invitations** via `learner_number` field  
✅ **Legacy learner fields** (learnerNumber, admission_number)  
✅ **Mixed school_id formats** (ObjectId and String)  
✅ **Multiple phone formats** (27xxxxxxxx and 0xxxxxxxx)  
✅ **Historical data inconsistencies** via fallback queries

---

## 🚀 Future Enhancements

### Planned Features
- [ ] Email invitation support
- [ ] SMS gateway integration
- [ ] Invitation templates
- [ ] Reminder notifications
- [ ] Analytics dashboard
- [ ] Bulk invitation upload (CSV)
- [ ] Custom expiration times
- [ ] Multi-language support

### Technical Improvements
- [ ] Redis caching layer
- [ ] Async job processing (Sidekiq)
- [ ] Rate limiting
- [ ] GraphQL API
- [ ] Webhook notifications

---

## 📚 Related Documentation

- [API Reference](./API.md)
- [Service Architecture](./SERVICE_ARCHITECTURE.md)
- [Data Models](./DATA_MODELS.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Troubleshooting](./TROUBLESHOOTING.md)

---

**Maintained by:** School Platform Team  
**Last Updated:** December 29, 2025  
**Version:** 2.0.0  
**License:** Proprietary