# Messaging System: File & Image Attachments (Phase 7.3)

This document summarizes the changes implemented to support file and image attachments in the messaging system using Cloudinary as the storage provider.

## 1. Data Model (Mongoid)
- **Model**: `app/models/message.rb`
- **New Fields**:
  - `attachment_url` (String): The public URL of the uploaded file.
  - `attachment_type` (String): The MIME type or category (e.g., `image/jpeg`, `pdf`).
  - `attachment_name` (String): The original filename.
  - `attachment_size` (Integer): The file size in bytes.
- **Validation Logic**:
  - `content` is now optional **if** `attachment_url` is present. This allows for image-only or file-only messages.
- **ID Consistency**:
  - Ensured `sender_id` and `user_id` are both present for robust frontend comparison logic.

## 2. Secure Upload Flow (Cloudinary)
- **Controller**: `app/controllers/api/v1/uploads_controller.rb`
- **Endpoints**:
  - `GET /api/v1/uploads`: Generates a signature for client-side uploads.
  - `POST /api/v1/uploads`: Same as above, provided for frontend flexibility.
- **Security**:
  - Uses `Cloudinary::Utils.api_sign_request` on the server to generate HMAC signatures.
  - Keeps the `API_SECRET` secure on the backend.
  - Returns `signature`, `timestamp`, `api_key`, and `cloud_name` as strings.
  - Supports signing additional parameters like `folder` and `upload_preset`.
- **Fallback**: Includes a mock signature generator for development environments without Cloudinary configuration.

## 3. Controller Alignment
- **Controller**: `app/controllers/api/v1/messages_controller.rb`
- **Strong Parameters**: Now permits all attachment metadata fields.
- **Association Fix**: Replaced `@message.user = sender` with `@message.sender = sender` to match the model's `belongs_to :sender` association.
- **ID Management**: Explicitly sets both `sender_id` and `user_id` to `sender.id.to_s` during message creation.
- **Serialization**: Updated to use `MessageSerializer` for both `index` and `create` actions to ensure consistent JSON output.

## 4. Serialization & Real-Time Broadcasting
- **Serializer**: `app/serializers/message_serializer.rb`
- **Broadcasting**: Handled via an `after_create` block in the `Message` model.
- **Payload**: Both the REST API and Action Cable WebSocket broadcasts now include:
  - Text content
  - Sender/User IDs
  - Full attachment metadata (URL, name, type, size)

## 5. Environment & Dependencies
- **Gem**: Added `cloudinary` to the `Gemfile`.
- **Environment Variables Required**:
  - `CLOUDINARY_CLOUD_NAME`
  - `CLOUDINARY_API_KEY`
  - `CLOUDINARY_API_SECRET` (or a single `CLOUDINARY_URL`)
