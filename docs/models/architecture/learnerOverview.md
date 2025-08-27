# 📄 Learner Model Update Overview

This document details the integration of **new mobile app fields** into the existing `Learner` model while retaining **legacy fields and business logic** for backward compatibility.

---

## 🔄 Key Updates

### ✅ **Kept Legacy Fields**
- **Personal Info:** `first_name`, `last_name`, `accession_number`
- **Contact Info:** `phone`, `whatsapp`, `telegram`, `tel_home`, `tel_emergency`
- **Status & Gender:** enums (`GENDERS`, `STATUSES`), helper methods, scopes (`active`, `inactive`, `graduated`)
- **Callbacks:** accession number auto-generation, phone sanitization
- **Helpers:** `add_school`, `school_name`, `grade_name`, `primary_contact`, `emergency_contact`
- **Serializer:** `to_api_hash` still returns full legacy + new attributes

### ✅ **Added Mobile App Fields**
- `date_of_birth` → learner’s birthdate
- `parent_info` (Hash) → flexible parent/guardian details
- `enrollment_date` → enrollment tracking
- `mobile_sync_id` → unique identifier for syncing with mobile app
- `last_sync_at` → timestamp for last synchronization

### ✅ **Indexes**
- Kept existing indexes for legacy fields
- Added:
  - `index({ mobile_sync_id: 1 }, { unique: true, sparse: true })`
  - `index({ school_id: 1, last_sync_at: 1 })`

---

## 🚀 Impact
- **Backward Compatibility:** Existing web functionality remains intact.  
- **Mobile Parity:** Model now supports required fields for mobile sync.  
- **Performance:** Sync-specific indexes improve scalability.  
- **Unified Serialization:** API consumers get both legacy and new fields without breaking changes.  

---

## 📌 Next Steps
1. Update API controllers to expose new fields in sync endpoints.  
2. Adjust mobile sync service to leverage `mobile_sync_id` and `last_sync_at`.  
3. Ensure test coverage for both legacy and new fields.  
4. Plan gradual migration of old contact fields into `parent_info`.  

---
