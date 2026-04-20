# Mongoid Architect Audit Report

## 1. Document Design Critique

### Nesting Strategy
- **Successes:** `User` correctly embeds `OnboardingStatus`. Since onboarding data is tightly coupled with user state and always retrieved together, embedding is the optimal strategy.
- **Unbound Arrays (Risks):**
    - `School#adminUsers` and `School#invites` are stored as `Array` fields. If a school grows significantly, these arrays will lead to document size bloat and performance degradation (reaching the 16MB BSON limit).
    - `Learner#parent_info` stores parent details in a Hash/Array. This should be monitored to ensure it doesn't grow indefinitely.
    - **Recommendation:** Convert `School#adminUsers` and `School#invites` to referenced associations (`has_many`) or use a dedicated `UserSchoolRole` collection (which is already partially implemented but inconsistently used).

### Relational vs. Document Thinking
- **Relational Remnants:** The use of join models like `UserSchoolRole` and `TeacherGradeAssignment` reflects relational architecture. While necessary for complex permissions, ensure that queries against these don't lead to "N+1 for NoSQL".
- **Broken Joins:** `User#teaching_grades` uses `Grade.joins(:teacher_grade_assignments)`. Mongoid does **not** support `.joins`. This code will likely fail or return unexpected results if it relies on ActiveRecord-style join logic.
- **Recommendation:** Replace `.joins` with criteria-based lookups, e.g., `Grade.in(id: teacher_grade_assignments.pluck(:grade_id))`.

---

## 2. Consistency & Types Audit

### Naming Inconsistency
- The codebase is a mix of camelCase (`schoolName`, `schoolEmail`, `gradeId`) and snake_case (`first_name`, `last_name`).
- **Recommendation:** Standardize on snake_case for all field definitions to align with Rails conventions and prevent developer confusion. Use `alias_attribute` if legacy frontend support is required for camelCase.

### Dynamic Attributes
- Models like `Invitation`, `Event`, `Student`, and `Transaction` include `Mongoid::Attributes::Dynamic`.
- **Risk:** This allows unvalidated data to be persisted, potentially leading to "pollution" of the document schema.
- **Recommendation:** Remove `Mongoid::Attributes::Dynamic` and explicitly define all fields to maintain schema integrity and take advantage of Mongoid's type casting.

---

## 3. Performance & Query Optimization

### Ruby-Side Filtering
- `Account` model uses `payment_history.select { ... }` for calculating balances and last payments.
- **Performance Killer:** As the `payment_history` array grows, every instantiation of the `Account` model will become increasingly expensive.
- **Recommendation:** Use MongoDB's `$slice` to get recent history or, better yet, use a separate `Payment` collection and perform indexed queries.

### Serialization N+1
- `School#to_api_hash` performs multiple counts (`UserSchoolRole.where(...)`, `Learner.where(...)`) for every school.
- **Recommendation:** Use counter caches or perform a single aggregation to fetch stats for multiple schools in one round-trip.

### Atomic Updates
- `Transaction#update_user_and_school_accounts` uses `model.update(attr: val)`.
- **Race Condition Risk:** `user.update(cash_account: user.cash_account - amount)` is not atomic. Two simultaneous transactions could lead to incorrect balances.
- **Recommendation:** Use Mongoid's atomic operators: `user.inc(cash_account: -amount)` and `school.inc(cash_account: amount)`.

---

## 4. Service Layer & Callbacks Audit

### Callback Side-Effects
- `Transaction` has heavy `after_save` callbacks that modify other documents (`User`, `School`).
- **Risk:** If the secondary update fails, the system is left in an inconsistent state. Mongoid doesn't support multi-document transactions in the same way ActiveRecord does (without explicit session management).
- **Recommendation:** Move financial orchestration logic out of model callbacks and into a `TransactionService`. Use MongoDB sessions if consistency is critical.

### Business Logic Leakage
- Business logic for progress calculation is leaking into `OnboardingStatus` callbacks.
- **Recommendation:** Keep models "thin" by moving complex state transitions to the `OnboardingStatusService`.

---

## Summary of Action Items
1.  **Refactor Financial Updates:** Switch to `.inc` for cash account updates.
2.  **Fix Broken Queries:** Remove `.joins` from `User.rb`.
3.  **Schema Cleanup:** Remove `Mongoid::Attributes::Dynamic` where not strictly required.
4.  **Indexing:** Ensure `payment_history` is not being filtered in Ruby; move to collection-based queries.
5.  **Standardize Naming:** Migrate fields to snake_case.
