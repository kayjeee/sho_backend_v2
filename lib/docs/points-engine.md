# Points Engine Documentation

## Purpose
A positive-only reinforcement system to encourage good behavior and participation.

## Data Flow
- Teacher selects a student or group.
- Teacher selects a positive skill (Participation, Teamwork, etc.).
- System records the point and updates the student's total.
- **NO negative scoring allowed.**

## API Endpoints / Server Actions
- `awardPoint(studentId, categoryId)`: Awards a point to a specific student.
- `awardPointToGroup(groupId, categoryId)`: Awards a point to all students in a group.
- `getPointHistory(studentId)`: Retrieves the history of points for a student.

## AI Extension Hooks
- `behaviorTrendDetector.ts`: Analyzes point history to detect peaks or dips in engagement.
- `reinforcementAnalyzer.ts`: Suggests students who haven't received feedback recently.

## Logging Strategy
`console.log("[POINT_AWARDED]", { schoolId, userId, timestamp, metadata: { studentId, skill } })`

## Future Scaling Notes
- Customizable point weightings.
- Exportable behavior reports for parents and admins.
