# Project Folder Structure

```text
/
├── app/
│   ├── schools/
│   │   └── [schoolSlug]/
│   │       ├── teacher/
│   │       │   ├── invite/
│   │       │   │   └── [inviteToken]/
│   │       │   │       └── page.tsx      # Invite validation & onboarding
│   │       │   └── dashboard/
│   │       │       ├── classroom/        # Digital Classroom
│   │       │       ├── story/            # Class Story
│   │       │       └── messages/         # Messaging
│   │       └── layout.tsx                # Tenant-specific layout
│   └── layout.tsx
├── components/
│   ├── classroom/                        # Classroom UI components
│   ├── points/                           # Points UI
│   ├── shared/                           # Reusable UI (Buttons, Cards, etc.)
│   └── ui/                               # Shadcn/UI (if applicable)
├── lib/
│   ├── actions/                          # Next.js Server Actions
│   │   ├── invite.ts
│   │   ├── classroom.ts
│   │   ├── points.ts
│   │   └── messaging.ts
│   ├── ai/                               # AI Extension Layer
│   │   ├── reinforcementAnalyzer.ts
│   │   ├── parentEngagementScore.ts
│   │   └── behaviorTrendDetector.ts
│   ├── db/                               # MongoDB connection & models
│   │   ├── mongodb.ts
│   │   └── models.ts
│   ├── docs/                             # Technical Documentation
│   └── validations/                      # Zod Schemas
│       ├── invite.ts
│       └── classroom.ts
└── public/
    └── avatars/                          # Student avatars
```
