# Database Schema Proposal

## Collections

### schools
- `_id`: ObjectId
- `name`: String
- `slug`: String
- `config`: { `quietHours`: { `start`: String, `end`: String } }

### teachers
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `auth0Id`: String (Indexed)
- `name`: String
- `email`: String

### classrooms
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `teacherId`: ObjectId (Indexed)
- `name`: String
- `grade`: String

### students
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `classroomId`: ObjectId (Indexed)
- `name`: String
- `avatar`: String
- `parentAuth0Ids`: Array<String>

### groups
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `classroomId`: ObjectId (Indexed)
- `name`: String
- `studentIds`: Array<ObjectId>

### projects
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `groupId`: ObjectId (Indexed)
- `name`: String
- `description`: String
- `status`: String (pending/active/completed)

### points
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `studentId`: ObjectId (Indexed)
- `teacherId`: ObjectId (Indexed)
- `category`: String
- `points`: Integer (Always > 0)
- `createdAt`: Timestamp

### messages
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `senderId`: String
- `receiverId`: String
- `text`: String
- `status`: String (sent/delivered/read)
- `createdAt`: Timestamp

### stories
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `teacherId`: ObjectId (Indexed)
- `content`: String
- `images`: Array<String>
- `comments`: Array<{ `userId`: String, `text`: String, `createdAt`: Timestamp }>
- `createdAt`: Timestamp

### portfolios
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `studentId`: ObjectId (Indexed)
- `content`: String
- `mediaUrl`: String
- `feedback`: String
- `createdAt`: Timestamp

### attendance
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `classroomId`: ObjectId (Indexed)
- `date`: Date
- `records`: Array<{ `studentId`: ObjectId, `status`: String (present/absent/late) }>

### invites
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `tokenHash`: String (Indexed)
- `email`: String
- `expiresAt`: Timestamp
- `status`: String

### audit_logs
- `_id`: ObjectId
- `schoolId`: String (Indexed)
- `userId`: String (Indexed)
- `action`: String
- `metadata`: Object
- `timestamp`: Timestamp
