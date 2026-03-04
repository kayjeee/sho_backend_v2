# Messaging & Stories Documentation

## Purpose
Facilitates communication between teachers and parents via private messages and public class stories.

## Data Flow
### Private Messaging
- Teacher or Parent sends a message.
- System checks "Quiet Hours" before sending notifications.
- Message status updates to "Delivered" and then "Read".

### Class Story
- Teacher posts an update (text/image).
- Parents view the update and can leave comments.

## API Endpoints / Server Actions
- `sendMessage(receiverId, content)`: Sends a private message.
- `updateMessageStatus(messageId, status)`: Updates status (delivered/read).
- `createStoryPost(content, images)`: Creates a new class story.
- `addStoryComment(storyId, content)`: Adds a comment to a story.

## AI Extension Hooks
- `parentEngagementScore.ts`: Measures engagement based on story views, comments, and message response times.
- `recommendPositiveMessage.ts`: Suggests encouraging messages to send to parents.
- `storySummarizer.ts`: Provides a weekly summary of class stories for busy parents.

## Logging Strategy
`console.log("[MESSAGE_SENT]", { schoolId, userId, timestamp, metadata: { receiverId } })`
`console.log("[STORY_POSTED]", { schoolId, userId, timestamp, metadata: { storyId } })`

## Future Scaling Notes
- Push notifications using Firebase or Ably.
- Multi-language support for message translation.
