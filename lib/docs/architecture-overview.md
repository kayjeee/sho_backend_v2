# Teacher Engagement System - Architecture Overview

## Purpose
The Teacher Engagement System is designed to empower teachers with tools for classroom management, student motivation through positive reinforcement, and seamless parent communication. It is a multi-tenant system where each school operates in isolation.

## Architecture Decisions
- **Stack**: Next.js (App Router), MongoDB, Server Actions.
- **Multi-tenancy**: Mandatory `schoolId` on all database queries and actions.
- **Authentication**: JWT-based for testing; Invite tokens for teacher onboarding.
- **AI-Ready**: Logic isolated in `/lib/ai/` to allow for plug-and-play AI modules.

## Core Modules
1. **Invite System**: Token-based teacher onboarding with 7-day expiration.
2. **Digital Classroom**: Student management and avatar assignment.
3. **Points Engine**: Positive reinforcement only (ClassDojo style).
4. **Messaging**: Secure Teacher-Parent communication with "Quiet Hours".
5. **Class Story**: Social feed for classroom updates.

## Data Flow
Teacher visits `/schools/[schoolSlug]/teacher/invite/[inviteToken]`.
-> Server Action validates `schoolSlug` and `inviteToken`.
-> If valid, teacher proceeds to onboarding.
-> Teacher creates `Classroom` and adds `Students`.
-> Points, Stories, and Messages are tracked with `schoolId` and `audit_logs`.

## Logging Strategy
Structured logging for all actions:
`console.log("[FEATURE_NAME_ACTION]", { schoolId, userId, timestamp, metadata })`

## Future Scaling
- Sharding MongoDB by `schoolId`.
- Edge functions for AI analysis.
- Real-time updates using WebSockets/Ably.
