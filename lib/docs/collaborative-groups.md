# Collaborative Groups Documentation

## Purpose
Enables teachers to organize students into groups for projects and collaborative learning.

## Data Flow
- Teacher creates a `Group` within a `Classroom`.
- Teacher assigns `Students` to the `Group`.
- Teacher creates `Projects` and assigns them to `Groups`.

## API Endpoints / Server Actions
- `createGroup(classroomId, name)`: Creates a new student group.
- `addStudentToGroup(groupId, studentId)`: Assigns a student to a group.
- `createGroupProject(groupId, projectDetails)`: Assigns a project to a group.

## AI Extension Hooks
- `groupDynamicsAnalyzer.ts`: Analyzes group performance and suggests optimal student pairings.

## Logging Strategy
`console.log("[GROUP_CREATED]", { schoolId, userId, timestamp, metadata: { groupId, classroomId } })`

## Future Scaling Notes
- Student-led group creation (optional).
- Peer review system within groups.
