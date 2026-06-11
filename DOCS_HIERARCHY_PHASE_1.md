# School Management Hierarchy Phase 1 - Frontend Integration Guide

This document outlines the API changes and new endpoints introduced in Phase 1 of the multi-tier school management hierarchy transition.

## Data Structure Changes

### 1. Grade Model (`Grade`)
Now contains a collection of Classes.
- **New Association**: `has_many :school_classes`
- **New Helper**: `total_learners` (Returns aggregate count of learners across all classes in the grade).

### 2. Class Model (`SchoolClass`)
Represents a specific class unit (e.g., "9A") within a Grade.
- **Fields**:
  - `name`: (String) e.g., "9A"
  - `capacity`: (Integer) Default: 40
  - `class_teacher_id`: (String) Auth0 ID or Teacher reference.
  - `subject_teacher_ids`: (Hash) `{ "subject_id" => "teacher_id" }`
  - `learner_ids`: (Array of ObjectIds) References to `Learner` documents.

---

## API Reference

### Global Search
Search across Learners, Grades, and Classes within a specific school context.

**Endpoint**: `GET /api/v1/schools/:school_id/global_search?q=:query`

**Response**:
```json
{
  "success": true,
  "results": [
    { "type": "Learner", "label": "John Doe", "value": "6519b3..." },
    { "type": "Grade", "label": "Grade 9", "value": "6519b4..." },
    { "type": "Class", "label": "9A", "value": "6519b5..." }
  ]
}
```

---

### School Classes Management
Endpoints for managing classes within a grade.

| Action | Method | Route |
| :--- | :--- | :--- |
| List Classes | `GET` | `/api/v1/schools/:school_id/grades/:grade_id/classes` |
| Get Class Details | `GET` | `/api/v1/schools/:school_id/grades/:grade_id/classes/:id` |
| Create Class | `POST` | `/api/v1/schools/:school_id/grades/:grade_id/classes` |
| Update Class | `PATCH/PUT` | `/api/v1/schools/:school_id/grades/:grade_id/classes/:id` |
| Delete Class | `DELETE` | `/api/v1/schools/:school_id/grades/:grade_id/classes/:id` |

**Create/Update Payload**:
```json
{
  "class": {
    "name": "10B",
    "capacity": 35,
    "class_teacher_id": "auth0|..."
  }
}
```

---

### Teacher Assignments
Assign a class teacher or a subject-specific teacher.

**Endpoint**: `POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/assign_teacher`

**Payload**:
```json
{
  "teacher_id": "auth0|...",
  "role": "class_teacher" | "subject_teacher",
  "subject_id": "math_101" (Required for subject_teacher)
}
```

---

### Learner Movement
Transactionally move a learner from one class to another within the same grade hierarchy.

**Endpoint**: `POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/move_learner`

**Payload**:
```json
{
  "learner_id": "6519b7...",
  "target_class_id": "6519b8..."
}
```

---

## Deployment Fixes (Render)

The following deployment fixes have been applied for Render:
- **render.yaml**: Renamed and configured with `MONGODB_URI` and `SECRET_KEY_BASE`.
- **ActiveRecord Disabled**: ActiveRecord and its components (like ActionText) have been disabled to prevent connection errors in a Mongoid-only environment.
- **Warning Suppression**: Mongoid "Overwriting existing field" warnings are suppressed in production.
- **Environment Variables**: The application now prioritizes environment variables for configuration, adhering to a "pure .env" setup.

---

## Integration Tips

1. **BSON Guardrails**: The API handles invalid ObjectIds gracefully. If a 404 is returned, check if the ID strings passed in the URL or payload are valid MongoDB ObjectIds.
2. **Atomic Operations**: Learner movement is performed using MongoDB atomic operators (`$pull` and `$addToSet`) to prevent race conditions and ensure data integrity.
3. **Role Persistence**: When assigning a `subject_teacher`, the `subject_id` is used as a key in the `subject_teacher_ids` hash. Updating an existing `subject_id` will overwrite the previous teacher assignment for that subject.
