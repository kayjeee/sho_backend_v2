Below is **everything you need**:

✅ **A complete Postman test plan**
✅ **Curl commands for each step**
✅ **A clean architecture diagram showing the full flow**
(Invitation → Verify → Auth0 Login → Rails Login + Session Binding → User Created / School Added)

---

# ✅ **1. Test Plan (Postman – Full Scripted Collection)**

You will perform the flow in **4 stages**:

---

## **🟦 Step 1 — Create Invitation**

### **POST** `/api/v1/invitations`

Used by admins/teachers to send an invitation to a parent.

**Body (JSON):**

```json
{
  "phone_number": "+27821234567",
  "school_id": "6768f2e2bfa92dec73361a01",
  "parent_name": "John Doe",
  "role": "parent",
  "learner_ids": ["6768f2e2bfa92dec73361a44"]
}
```

### **Expected Response**

```json
{
  "success": true,
  "message": "Invitation sent successfully.",
  "invitation": {
    "id": "6768f4bfbfa92dec73361a90",
    "token": "f91a86c3-efe4-4d19-8f3c-7a0fb2fa5599",
    "recipient_phone_number": "+27821234567",
    "role": "parent",
    "status": "pending"
  }
}
```

### **Postman Test Script**

```js
pm.test("Invitation created", function () {
  pm.response.to.have.status(201);
  const data = pm.response.json();
  pm.expect(data.success).to.be.true;

  pm.collectionVariables.set("INVITATION_TOKEN", data.invitation.token);
  pm.collectionVariables.set("INVITATION_ID", data.invitation.id);
});
```

### **Curl**

```bash
curl -X POST http://localhost:4000/api/v1/invitations \
  -H "Content-Type: application/json" \
  -d '{"phone_number":"+27821234567","school_id":"6768f2e2bfa92dec73361a01","parent_name":"John Doe","role":"parent","learner_ids":["6768f2e2bfa92dec73361a44"]}'
```

---

## **🟧 Step 2 — Verify Invitation (via link)**

This is what happens when a parent clicks the link:

```
https://yourclient.com/parent?token={{INVITATION_TOKEN}}
```

Your frontend calls:

### **GET** `/api/v1/invitations/verify_with_details?token={{INVITATION_TOKEN}}`

### **Expected Response**

```json
{
  "success": true,
  "invitation": {
    "id": "6768f4bfbfa92dec73361a90",
    "recipient_phone_number": "+27821234567",
    "school_id": "6768f2e2bfa92dec73361a01",
    "learner_ids": ["6768f2e2bfa92dec73361a44"],
    "parent_name": "John Doe"
  }
}
```

### **What Rails Does Here**

* Stores the token in session:

```ruby
session[:invitation_token] = token
```

### **Postman Test Script**

```js
pm.test("Invitation verified and session saved", function () {
  pm.response.to.have.status(200);
  const data = pm.response.json();
  pm.expect(data.success).to.be.true;
});
```

### **Curl**

```bash
curl "http://localhost:4000/api/v1/invitations/verify_with_details?token={{INVITATION_TOKEN}}"
```

---

## **🟩 Step 3 — User Logs In via Auth0**

Frontend receives Auth0 token → then calls:

### **POST** `/api/v1/authentication/login`

**Body (JSON):**

```json
{
  "access_token": "{{AUTH0_ACCESS_TOKEN}}"
}
```

### **Rails Does:**

1. Validates token with Auth0
2. Finds or creates user
3. Checks if `session[:invitation_token]` exists
4. If yes:

   * Attach `school_id` from invitation
   * Attach phone number
   * Mark invitation as used
   * Remove `session[:invitation_token]`

### **Expected Response**

```json
{
  "success": true,
  "user": {
    "id": "USER123",
    "email": "parent@gmail.com",
    "phone_number": "+27821234567",
    "schools": ["6768f2e2bfa92dec73361a01"]
  }
}
```

### **Postman Test Script**

```js
pm.test("User logged in and invitation linked", function () {
  pm.response.to.have.status(200);
  const user = pm.response.json().user;

  pm.expect(user.phone_number).to.eq("+27821234567");
  pm.expect(user.schools).to.include("6768f2e2bfa92dec73361a01");
});
```

### **Curl**

```bash
curl -X POST http://localhost:4000/api/v1/authentication/login \
  -H "Content-Type: application/json" \
  -d '{"access_token":"{{AUTH0_ACCESS_TOKEN}}"}'
```

---

# 🟦 Step 4 — Assert Invitation Was Updated

### **GET** `/api/v1/invitations/{{INVITATION_ID}}` (if you have this endpoint)

Expected:

```json
{
  "status": "used",
  "user_id": "USER123"
}
```

---

# ✅ **2. Full End-to-End Test Flow Summary**

```
1. Admin Creates Invitation → returns TOKEN
2. Parent clicks link → verify_with_details → stores session[:invitation_token]
3. User logs into Auth0 → receives access_token
4. POST /login with access_token → Rails links user + invitation + school
5. Invitation becomes "used"
```

---

# 🎯 **3. Architecture Flow Diagram (Clean + Readable)**

```
┌───────────────────────────┐
│      Admin / Teacher      │
└─────────────┬─────────────┘
              │
              │ POST /invitations
              ▼
      ┌─────────────────────┐
      │   Rails Backend     │
      │ Creates Invitation  │
      │ Returns TOKEN       │
      └─────────┬───────────┘
                │
                │
                ▼
      ┌───────────────────────┐
      │  Parent Clicks Link   │
      │ /verify_with_details  │
      └───────────┬───────────┘
                  │
                  │ Stores token in SESSION
                  ▼
     ┌─────────────────────────┐
     │ Parent Logs in via      │
     │ Auth0 → access_token    │
     └───────────┬────────────┘
                 │
                 │ POST /login
                 ▼
       ┌───────────────────────────┐
       │ Rails Validates Token     │
       │ Finds or Creates User     │
       │ Checks session token      │
       │ Adds phone + school       │
       │ Marks invitation “used”   │
       └───────────┬──────────────┘
                   │
                   ▼
         ┌───────────────────────┐
         │     Parent Logged In  │
         │   + Linked to School  │
         └────────────────────────┘
```

---

# ✅ **If you want, I can also generate:**

### ✔️ A full Postman export (JSON file)

### ✔️ A Mermaid.js diagram for your docs

### ✔️ A README for your onboarding system

### ✔️ Tests (RSpec) for invitation → verify → login flow

Just tell me **“Generate Postman collection JSON”** or **“Give me the RSpec tests”**.
