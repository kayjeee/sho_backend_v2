# Teacher Invitation Model & Service Updates

## Model: `TeacherInvitation`
The model already has most of the required fields but needs validation updates and helper methods to match the `LearnerInvitation` pattern.

### Updated Fields & Validations
- Ensure `recipient_phone_number` is mandatory.
- Add `teacher_name` field.
- Update `to_api_hash` to include `full_magic_link`.

## Service: `InviteTeacherService`
Update the service to handle phone-based parameters and align with the new documentation.

### Changes
- Update `initialize` to accept phone-based params.
- Update `validate_invitation_constraints` to check for existing pending phone invitations.
- Update `create_invitation` to use the new parameters.
- Ensure `school_id` and `grade_id` are correctly associated.

## Controller: `GradesController`
- Update `teacher_invitation_params` to permit phone and name fields.
- Ensure the `invite_teacher` action calls the updated service correctly.

## Proposed `to_api_hash` for `TeacherInvitation`
```ruby
def to_api_hash
  school = School.where(id: school_id).first
  school_slug = school&.slug || school&.name&.parameterize || "unknown-school"

  {
    id: id.to_s,
    token: token,
    status: status,
    role: role,
    recipient_phone_number: recipient_phone_number,
    teacher_name: teacher_name,
    school_id: school_id,
    school_name: school&.schoolName,
    school_slug: school_slug,
    grade_id: grade_id,
    grade_ids: grade_ids,
    invited_via: invited_via,
    invited_at: invited_at,
    expires_at: expired_at,
    magic_link_query: "?token=#{token}&school=#{URI.encode_www_form_component(school&.schoolName || '')}",
    full_magic_link: "http://localhost:3000/schools/#{school_slug}/teacher/invite/#{token}"
  }
end
```
