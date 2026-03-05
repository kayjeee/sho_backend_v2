# Teacher Invitation Flow Documentation

## Purpose
Enables school administrators and senior teachers to invite new teachers to the platform via magic links sent through WhatsApp or SMS. This flow ensures a smooth onboarding process without requiring immediate account creation.

## Data Flow
1. **Initiation**: Admin calls `POST /api/v1/grades/:id/invite_teacher` with recipient phone number and invited channel.
2. **Generation**: `InviteTeacherService` validates permissions and constraints, then creates a `TeacherInvitation` record.
3. **Communication**: A magic link is generated and sent to the teacher.
4. **Acceptance**: Teacher clicks the link: `http://localhost:3000/schools/[schoolSlug]/teacher/invite/[inviteToken]`.
5. **Onboarding**: Upon acceptance, the teacher record is updated, and roles/school associations are finalized.

## API Endpoints
### POST /api/v1/grades/:id/invite_teacher
- **Payload**:
  ```json
  {
    "invitation": {
      "recipient_phone_number": "27821234589",
      "teacher_name": "John Doe",
      "invited_via": "whatsapp",
      "assigned_grades": ["grade_id_1", "grade_id_2"]
    }
  }
  ```
- **Response**: Success/Failure with invitation details.

## AI Extension Hooks
- `engagementOptimizer.ts`: Analyzes invitation response times to suggest the best channel (WhatsApp vs. SMS) for future invites.

## Logging Strategy
`console.log("[TEACHER_INVITATION_SENT]", { schoolId, userId, timestamp, metadata: { recipientPhone, invitedVia } })`

## Future Scaling Notes
- Bulk invitation via CSV upload.
- Automated follow-up reminders for pending invitations.
