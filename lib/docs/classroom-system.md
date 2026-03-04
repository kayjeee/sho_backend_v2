# Classroom System Documentation

## Purpose
Manages the digital representation of a physical classroom, including students and their metadata.

## Data Flow
- Teacher creates a `Classroom`.
- Teacher adds `Students` to the `Classroom`.
- Each `Student` is assigned a unique avatar.

## API Endpoints / Server Actions
- `createClassroom(data)`: Validates school isolation and creates classroom.
- `addStudent(classroomId, studentData)`: Adds a student to a specific classroom.
- `updateStudent(studentId, studentData)`: Updates student details like avatar or name.

## AI Extension Hooks
- `suggestStudentGroups()`: AI analyzes student performance to suggest balanced groups.

## Logging Strategy
`console.log("[CLASSROOM_CREATED]", { schoolId, teacherId, timestamp, metadata: { classroomId } })`

## Future Scaling Notes
- Support for multiple teachers per classroom.
- Integration with external School Information Systems (SIS).
