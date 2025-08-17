Grades Services Overview
This document provides an overview of the Grades-related service classes in the application, which encapsulate all business logic for managing school grades, including their creation, update, deletion, and invitations for teachers and learners.

Service Classes
1. CreateGradeService
Purpose: Handles the creation of new Grade records associated with a specific School.

Key Features:

Accepts school and grade_params as input, with an optional user argument.

Validates permissions if a user is provided (this feature has been made optional).

Builds and saves a new Grade document in MongoDB.

Returns a structured ServiceResult indicating success, created grade instance, or errors.

Does not require or assign created_by to allow flexible usage without user context.

Benefits: Clear separation of creation logic, validation, and error handling with consistent result format.

2. UpdateGradeService
Purpose: Handles updates to existing Grade records, including special handling for status changes.

Key Features:

Accepts grade, grade_params, and optional user.

Validates permissions if a user is specified.

Handles status transitions (active, inactive, archived) with validation to prevent unsafe changes (e.g., cannot archive grades with active learners).

Uses MongoDB-friendly queries and returns a ServiceResult.

Logs success or failure of update operations.

Benefits: Ensures safe updates with permission control and business rule enforcement, returns clear outcome structure.

3. DeleteGradeService
Purpose: Handles deletion of Grade records via a soft-delete approach (archives the grade).

Key Features:

Accepts grade and optional user for permission validation.

Validates permission to delete and checks constraints such as no active learners, no pending invitations, and no active teacher assignments.

Performs soft delete by setting status to 'archived'.

Returns structured success or error results.

Benefits: Safe deletion respecting business dependencies without hard removal.

4. InviteTeacherService
Purpose: Manages sending invitations to teachers to join a specific Grade in a School.

Key Features:

Accepts grade, invitation_params, optional user.

Checks user permissions before proceeding.

Validates that no duplicate pending invitation exists for the provided teacher email.

Validates that the teacher is not already associated with the school.

Verifies that all assigned grades in the invitation belong to the same school.

Creates the invitation and sends notification email asynchronously.

Logs activity and returns a structured service result.

Benefits: Prevents duplicate or inconsistent invitations and enforces assignment validity.

5. InviteLearnerService
Purpose: Manages inviting learners to enroll in a Grade.

Key Features:

Inputs: grade, invitation_params, optional user.

Validates permission to invite learners.

Ensures the grade accepts new learners (is active and not full).

Checks for existing pending invitations by email or phone.

Creates learner invitation and logs activity.

Returns structured success/error result.

Benefits: Enforces enrollment rules and prevents duplicate learner invitations.

Common Implementation Notes
All services use a ServiceResult struct for uniform success/error reporting, which includes:

success (boolean)

errors (array of strings)

grade or invitation (when applicable)

user argument is optional across services to allow flexibility for authenticated or system-level operations.

Permission checks rely on user roles and relationship to the school, bypassed if no user given.

Mongoid-specific queries and conventions are used throughout (e.g., .where, .exists?, .pluck, BSON ObjectId handling).

Service methods are designed with clear separation of concerns: validation, permission checks, business logic, and data persistence.

Logging is added for all major CRUD operations and invitation handling, aiding observability.

Services perform robust validation of associated data to maintain database integrity (e.g., assigned grades belong to the correct school).

Summary
Together, these Grades services provide a robust, secure, and extensible foundation for managing grade-related workflows in the school management application, supporting:

Grade lifecycle operations (create, update with status management, soft delete)

Controlled invitations to learners and teachers with validation

Permission checks adaptable to different user contexts

Clean API via structured results, easing controller integration and error handling

If you need, I can also help prepare usage examples or controller integration snippets for these services.