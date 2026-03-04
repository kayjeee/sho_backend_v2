# Toolkit System Documentation

## Purpose
A collection of utility tools for teachers to manage classroom activities effectively.

## Features
- **Random Student Picker**: Selects a student randomly for participation.
- **Timer**: A classroom timer for activities and tests.
- **Attendance Tracker**: Records daily attendance for students.

## Data Flow
- Teacher triggers the **Random Picker**; system returns a student name.
- Teacher sets the **Timer**; UI handles the countdown.
- Teacher marks **Attendance**; system saves records to the database.

## API Endpoints / Server Actions
- `markAttendance(classroomId, date, attendanceData)`: Saves attendance for a classroom on a specific date.
- `getAttendanceReport(classroomId, startDate, endDate)`: Retrieves attendance history.

## AI Extension Hooks
- `attendanceTrendDetector.ts`: Identifies patterns in student absences.

## Logging Strategy
`console.log("[ATTENDANCE_MARKED]", { schoolId, userId, timestamp, metadata: { classroomId, date } })`
`console.log("[TOOL_USED]", { schoolId, userId, timestamp, metadata: { toolName: "RandomPicker" } })`

## Future Scaling Notes
- Additional tools like "Noise Meter" or "Music Player".
- Automated attendance via NFC or QR codes.
