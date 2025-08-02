# Users Component

This document provides an overview of the `users` component within the Ruby on Rails school CRM application. It outlines the responsibilities of user-related modules, their interactions, and how they adhere to the project's architectural and documentation standards.

## 1. Overview

The `users` component is responsible for managing all user-related functionalities within the application. This includes user creation, retrieval, role management, and association with schools. It interacts primarily with the `User` model and leverages dedicated service objects to encapsulate complex business logic, ensuring a clear separation of concerns and adherence to manageable file sizes.

## 2. Key Files and Directories

*   `app/controllers/api/v1/users_controller.rb`: Handles API requests related to users, acting as a thin layer that orchestrates calls to service objects.
*   `app/models/user.rb`: The primary model representing a user, responsible for data persistence and basic validations.
*   `app/services/user_services/`: Directory containing service objects that encapsulate user-specific business logic.
    *   `app/services/user_services/create_user_service.rb`: Handles the creation of new user records.
    *   `app/services/user_services/update_roles_service.rb`: Manages the assignment and modification of user roles.
    *   `app/services/user_services/add_school_service.rb`: Manages the association of users with schools.
    *   `app/services/user_services/fetch_schools_service.rb`: Retrieves schools associated with a user.
*   `app/forms/user_forms/` (Future): May contain form objects for complex user-related forms.
*   `app/policies/user_policy.rb` (Future): Will contain authorization logic for user resources.

## 3. API Endpoints (Handled by `Api::V1::UsersController`)

The `UsersController` exposes the following API endpoints:

*   `POST /api/v1/users`: Creates a new user.
*   `GET /api/v1/users/:id`: Retrieves details for a specific user.
*   `GET /api/v1/users/:id/schools`: Retrieves schools associated with a specific user.
*   `PATCH /api/v1/users/:id/roles`: Updates the roles of a specific user.
*   `PATCH /api/v1/users/:id/add_school`: Associates a school with a specific user.

## 4. Core Logic and Services

To maintain a thin controller and adhere to the 500-line file limit, complex business logic is delegated to dedicated service objects within the `app/services/user_services/` directory. Each service object is designed to perform a single, well-defined operation.

### 4.1. `UserServices::CreateUserService`

**Purpose:** Encapsulates the logic for creating a new user.

**Usage in Controller:**
```ruby
# In Api::V1::UsersController#create
result = UserServices::CreateUserService.call(user_params: user_params)
if result.success?
  # ... handle success
else
  # ... handle failure
end
```

### 4.2. `UserServices::UpdateRolesService`

**Purpose:** Handles the logic for updating a user's roles, including ensuring uniqueness of roles.

**Usage in Controller:**
```ruby
# In Api::V1::UsersController#update_roles
result = UserServices::UpdateRolesService.call(user: @user, new_roles: params[:roles])
if result.success?
  # ... handle success
else
  # ... handle failure
end
```

### 4.3. `UserServices::AddSchoolService`

**Purpose:** Manages the process of associating a school with a user, including validation of the `schoolId`.

**Usage in Controller:**
```ruby
# In Api::V1::UsersController#add_school
result = UserServices::AddSchoolService.call(user: @user, school_id: params[:schoolId])
if result.success?
  # ... handle success
else
  # ... handle failure
end
```

### 4.4. `UserServices::FetchSchoolsService`

**Purpose:** Retrieves a list of schools associated with a given user. This service encapsulates the logic for querying schools based on user's school IDs, including necessary data transformations.

**File Structure (`app/services/user_services/fetch_schools_service.rb`):**
```ruby
module UserServices
  class FetchSchoolsService < ApplicationService # Assuming ApplicationService is a base class for services
    def initialize(user:)
      @user = user
    end

    def call
      Rails.logger.debug "🏫 UserServices::FetchSchoolsService: Fetching schools for user #{@user.auth0_id}"
      
      school_ids = Array(@user.school_ids).map(&:to_s)
      schools = School.where(:_id.in => school_ids.map { |id| BSON::ObjectId.from_string(id) })
      
      Rails.logger.info "✅ UserServices::FetchSchoolsService: Found #{schools.count} school(s) for user #{@user.auth0_id}"
      schools
    end
  end
end
```

**Usage in Controller:**
```ruby
# In Api::V1::UsersController#schools
schools = UserServices::FetchSchoolsService.call(user: @user)

if schools.any?
  # ... render schools
else
  # ... handle no schools found
end
```

## 5. Documentation and Logging

Consistent with project standards, all files within the `users` component, especially the controller and service objects, include extensive in-code comments and console logging. This provides clear explanations of logic, execution flow, and debugging information, significantly aiding junior developers in understanding and troubleshooting the codebase.

## 6. Adherence to NASA Standards

The `users` component is designed with NASA's 

