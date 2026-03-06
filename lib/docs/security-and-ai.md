# Security & AI Extension Points

## Security Best Practices
1. **Token Hashing**: Invite tokens are stored using SHA-256 hashes.
2. **Tenant Isolation**: Every query must include `schoolId`. Middleware or a high-level wrapper should enforce this.
3. **RBAC**: User roles (Admin, Teacher, Parent) must be verified before performing actions.
4. **Input Validation**: Use Zod for all Server Action inputs.
5. **Rate Limiting**: Apply rate limiting to invite validation and messaging endpoints.

## AI Extension Layer (`/lib/ai/`)

### `reinforcementAnalyzer.ts`
- **Goal**: Identify students who haven't received positive points in a set period.
- **Input**: `points` collection filtered by `classroomId`.
- **Output**: List of students needing encouragement.

### `parentEngagementScore.ts`
- **Goal**: Score parent engagement based on story views, comments, and message responses.
- **Input**: `stories` and `messages` collections.
- **Output**: Engagement score (0-100).

### `behaviorTrendDetector.ts`
- **Goal**: Detect significant changes in classroom behavior trends.
- **Input**: Aggregated `points` data over time.
- **Output**: Trend report (Improving/Declining/Stable).

### `storySummarizer.ts`
- **Goal**: Summarize the week's class story posts for parents.
- **Input**: `stories` for the current week.
- **Output**: Short text summary.
