# Onboarding Status Plan Overview

## 1. Controller Summary

The `OnboardingStatusesController` manages user onboarding progress within the User collection.

### Key Actions

| Action | Endpoint | Purpose | Updates User? |
|--------|----------|---------|---------------|
| `show` | `GET /users/:user_id/onboarding_status` | Fetch current onboarding status | ❌ No changes |
| `update` | `PATCH /users/:user_id/onboarding_status` | Generic update to onboarding fields | ✅ Uses `$set` on provided params |
| `complete_step` | `POST /users/:user_id/onboarding_status/complete_step` | Mark step as completed | ✅ Delegates to OnboardingStatusService |
| `skip_step` | `POST /users/:user_id/onboarding_status/skip_step` | Add step to skipped array | ✅ Uses `$push` on skipped_steps |
| `reset` | `POST /users/:user_id/onboarding_status/reset` | Clear entire onboarding status | ✅ Uses `$set` |

## 2. Current Problem

```mermaid
flowchart TD
    A[User creates grades] -->|API call| B[OnboardingStatusesController#complete_step]
    B -->|Calls service| C[OnboardingStatusService]
    C -->|Updates| D["User.onboarding_status.create_grades = true"]
    
    E[User uploads learners] -->|API call| F[LearnersController#bulk_upload]
    F -->|No onboarding update| G["User.onboarding_status.upload_learners = false"]
    
    style G fill:#ffcccc
    style D fill:#ccffcc
```

**Issue**: Learner upload doesn't trigger onboarding status updates, leaving `upload_learners` as `false`.

## 3. Recommended Solution Architecture

### Service Separation Strategy

Instead of one shared onboarding service, we'll create dedicated services that communicate:

```mermaid
graph TB
    subgraph "Controllers"
        A[LearnersController]
        B[OnboardingStatusesController]
    end
    
    subgraph "Services"
        C[LearnerUploadService]
        D[OnboardingStatusService]
    end
    
    subgraph "Database"
        E[User Collection]
    end
    
    A -->|Delegates upload| C
    C -->|Notifies completion| D
    B -->|Direct calls| D
    C -->|Updates learner data| E
    D -->|Updates onboarding status| E
```

## 4. Implementation Plan

### Step 1: Create LearnerUploadService

```ruby
# app/services/learner_upload_service.rb
class LearnerUploadService
  def initialize(user, file_or_data)
    @user = user
    @file_or_data = file_or_data
  end

  def call
    # Process learner upload logic
    result = process_upload
    
    # Notify onboarding service on success
    if result[:success]
      OnboardingStatusService.mark_step_complete(@user, 'upload_learners')
    end
    
    result
  end

  private

  def process_upload
    # Your existing upload logic here
    # CSV parsing, validation, database inserts, etc.
  end
end
```

### Step 2: Update LearnersController

```ruby
# app/controllers/api/v1/learners_controller.rb
class Api::V1::LearnersController < ApplicationController
  def bulk_upload
    service = LearnerUploadService.new(@user, params[:file])
    result = service.call
    
    if result[:success]
      render json: { 
        success: true, 
        message: "Learners uploaded successfully",
        data: result[:data]
      }
    else
      render json: { 
        success: false, 
        errors: result[:errors] 
      }, status: :unprocessable_entity
    end
  end
end
```

### Step 3: Enhanced OnboardingStatusService

```ruby
# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def mark_step_complete(user, step_name, metadata = {})
      timestamp = Time.current.iso8601
      
      updates = {
        "onboarding_status.#{step_name}" => true,
        "onboarding_status.updated_at" => timestamp
      }
      
      # Add metadata if provided
      if metadata.any?
        updates["onboarding_status.#{step_name}_metadata"] = metadata
      end
      
      user.set(updates)
      
      Rails.logger.info "Onboarding step '#{step_name}' completed for user #{user.id}"
      
      {
        success: true,
        step: step_name,
        completed_at: timestamp,
        data: user.onboarding_status
      }
    end
  end
end
```

## 5. Updated Flow Diagram

```mermaid
flowchart TD
    A[User uploads learners] -->|POST request| B[LearnersController#bulk_upload]
    B -->|Delegates to| C[LearnerUploadService]
    
    C -->|Processes| D[CSV Parsing & Validation]
    D -->|Success?| E{Upload Successful?}
    
    E -->|Yes| F[Save learners to DB]
    E -->|No| G[Return errors]
    
    F -->|Notify| H[OnboardingStatusService.mark_step_complete]
    H -->|Updates| I["User.onboarding_status.upload_learners = true"]
    
    I -->|Response| J[Success JSON with onboarding status]
    G -->|Response| K[Error JSON]
    
    style F fill:#ccffcc
    style I fill:#ccffcc
    style G fill:#ffcccc
    style K fill:#ffcccc
```

## 6. Benefits of This Architecture

### 🎯 **Separation of Concerns**
- `LearnerUploadService`: Handles CSV processing, validation, database operations
- `OnboardingStatusService`: Manages onboarding status updates only
- Controllers stay thin and focused

### 🔄 **Clear Communication Flow**
```mermaid
sequenceDiagram
    participant C as LearnersController
    participant LUS as LearnerUploadService
    participant OSS as OnboardingStatusService
    participant DB as Database
    
    C->>LUS: call(user, file)
    LUS->>DB: Insert learner records
    DB-->>LUS: Success/Failure
    LUS->>OSS: mark_step_complete('upload_learners')
    OSS->>DB: Update onboarding_status
    DB-->>OSS: Confirmation
    OSS-->>LUS: Status result
    LUS-->>C: Final result with onboarding
```

### 🧪 **Easy Testing**
- Test learner upload logic independently
- Test onboarding updates separately
- Mock service interactions cleanly

### 📈 **Scalable**
- Add more upload types (e.g., BulkGradeUploadService)
- Each service can have its own validation rules
- Onboarding service remains reusable

## 7. Debugging & Monitoring

### Logging Strategy
```ruby
# In LearnerUploadService
Rails.logger.info "Starting learner upload for user #{@user.id}"

# In OnboardingStatusService
Rails.logger.info "Onboarding step completed: #{step_name} for user #{user.id}"
```

### Health Checks
```ruby
# Verify onboarding status after upload
user.reload
puts user.onboarding_status.upload_learners # Should be true
```

## 8. Migration Checklist

- [ ] Create `LearnerUploadService`
- [ ] Update `LearnersController` to use new service
- [ ] Enhance `OnboardingStatusService` with `mark_step_complete`
- [ ] Add logging and error handling
- [ ] Write unit tests for both services
- [ ] Test integration flow end-to-end
- [ ] Update API documentation

## 9. Future Enhancements

```mermaid
graph LR
    A[Current: Upload Learners] --> B[Future: Upload Grades]
    A --> C[Future: Import Assessments]
    A --> D[Future: Bulk User Creation]
    
    B --> E[OnboardingStatusService]
    C --> E
    D --> E
```

This architecture allows easy addition of new upload services while maintaining consistent onboarding status tracking.