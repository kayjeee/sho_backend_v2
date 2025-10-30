# Invitations Controller - Simplified Version

## 📋 Controller Purpose

This controller handles the creation and sending of invitations to users, specifically designed for internal/admin use cases where full authentication is not required.

## 🔧 Key Features

- **Admin-only access** - Only users with 'admin' role can send invitations
- **Email-based identification** - Users identified by email address without token authentication
- **Invitation service integration** - Delegates business logic to dedicated service class
- **RESTful response handling** - Returns appropriate JSON responses for success/error cases

## 🏗️ Architecture Flow

```mermaid
graph TD
    A[Client Request] --> B[InvitationsController#create]
    B --> C[authenticate_admin! Before Action]
    C --> D{current_user exists?}
    D -- No --> E[Return Unauthorized 401]
    D -- Yes --> F{User has admin role?}
    F -- No --> E
    F -- Yes --> G[UserServices::InvitationService]
    
    G --> H[Create Invitation Record]
    H --> I{Invitation Persisted?}
    I -- Yes --> J[Return Success 201]
    I -- No --> K[Return Errors 422]
    
    subgraph "User Identification"
        L[Params user_email] --> M[Find User by Email]
        N[Headers X-User-Email] --> M
    end
    
    M --> D
    
    style E fill:#ff6b6b
    style J fill:#51cf66
    style K fill:#ffd43b
    style G fill:#4dabf7
```

## 🔄 Complete Request/Response Flow

```mermaid
sequenceDiagram
    participant Client
    participant Controller
    participant Auth as authenticate_admin!
    participant UserModel as User Model
    participant Service as InvitationService
    participant DB as Database
    
    Client->>Controller: POST /api/v1/invitations
    Note over Client,Controller: Headers: X-User-Email or<br/>Params: user_email
    
    Controller->>Auth: Check authorization
    Auth->>UserModel: Find user by email
    
    alt User not found
        UserModel-->>Auth: nil
        Auth-->>Controller: Unauthorized
        Controller-->>Client: 401 Unauthorized
    else User found but not admin
        UserModel-->>Auth: User (no admin role)
        Auth-->>Controller: Unauthorized
        Controller-->>Client: 401 Unauthorized
    else User is admin
        UserModel-->>Auth: Admin User
        Auth-->>Controller: Authorized
        
        Controller->>Service: create_invitation(params)
        Service->>DB: Save invitation
        
        alt Save successful
            DB-->>Service: Invitation persisted
            Service-->>Controller: Success
            Controller-->>Client: 201 Created
        else Validation errors
            DB-->>Service: Validation failed
            Service-->>Controller: Error details
            Controller-->>Client: 422 Unprocessable Entity
        end
    end
```

## 🔐 Security Model

### Current Implementation

```mermaid
graph LR
    A[Incoming Request] --> B{Email Provided?}
    B -- No --> C[401 Unauthorized]
    B -- Yes --> D[Find User by Email]
    D --> E{User Exists?}
    E -- No --> C
    E -- Yes --> F{Has Admin Role?}
    F -- No --> C
    F -- Yes --> G[Process Invitation]
    
    style C fill:#ff6b6b
    style G fill:#51cf66
```

### Identification Methods

**Query Parameter:**
```
POST /api/v1/invitations?user_email=admin@school.edu
```

**Request Header:**
```
X-User-Email: admin@school.edu
```

## 🎯 Use Cases

### Intended Environments

```mermaid
graph TD
    A[Invitations API] --> B[Internal Microservices]
    A --> C[Server-to-Server Communication]
    A --> D[Development/Testing]
    A --> E[Trusted Network Apps]
    
    B --> F[Behind Firewall]
    C --> F
    D --> F
    E --> F
    
    F --> G[IP Whitelisting]
    F --> H[Rate Limiting]
    F --> I[Network Security]
    
    style A fill:#4dabf7
    style F fill:#ffd43b
```

### Sample Request

```bash
curl -X POST \
  http://localhost:3000/api/v1/invitations \
  -H 'Content-Type: application/json' \
  -H 'X-User-Email: admin@school.edu' \
  -d '{
    "phone_number": "+1234567890",
    "school_id": "507f1f77bcf86cd799439011"
  }'
```

## ⚠️ Security Considerations

### Risk Assessment

```mermaid
mindmap
  root((Security Risks))
    Email Spoofing
      Anyone can send admin email
      No identity verification
      Impersonation possible
    CSRF Vulnerabilities
      No token protection
      No origin validation
    Session Management
      No session tracking
      No logout mechanism
    Network Exposure
      Public API endpoint
      No IP restrictions
```

### Mitigation Strategy

```mermaid
graph TB
    A[Security Layers] --> B[Network Level]
    A --> C[Application Level]
    A --> D[Infrastructure Level]
    
    B --> B1[IP Whitelisting]
    B --> B2[Firewall Rules]
    B --> B3[VPN Requirements]
    
    C --> C1[Rate Limiting]
    C --> C2[Request Validation]
    C --> C3[Audit Logging]
    
    D --> D1[API Gateway]
    D --> D2[Load Balancer Rules]
    D --> D3[Container Network Policies]
    
    style A fill:#4dabf7
    style B fill:#51cf66
    style C fill:#ffd43b
    style D fill:#ff6b6b
```

### Compensation Strategies

- Use in firewalled environments only
- Implement IP whitelisting at network level
- Add request rate limiting
- Consider API key authentication as minimal protection
- Enable comprehensive audit logging
- Monitor for suspicious patterns

## 🔄 Dependencies

```mermaid
graph LR
    A[InvitationsController] --> B[User Model]
    A --> C[Role System]
    A --> D[InvitationService]
    
    B --> B1[email field]
    B --> B2[auth0_id field]
    
    C --> C1[has_role? method]
    
    D --> D1[Business Logic]
    D --> D2[Validation]
    D --> D3[Email Delivery]
    
    style A fill:#4dabf7
    style B fill:#51cf66
    style C fill:#ffd43b
    style D fill:#ff6b6b
```

## 📈 Response Examples

### Success (201)
```json
{
  "success": true,
  "message": "Invitation sent successfully."
}
```

### Unauthorized (401)
```json
{
  "success": false,
  "error": "You are not authorized to perform this action."
}
```

### Validation Error (422)
```json
{
  "success": false,
  "errors": ["Phone number is invalid", "School not found"]
}
```

## 📊 Response Status Flow

```mermaid
stateDiagram-v2
    [*] --> ValidateAuth
    ValidateAuth --> CheckAdmin: User Found
    ValidateAuth --> Return401: User Not Found
    
    CheckAdmin --> ProcessInvitation: Is Admin
    CheckAdmin --> Return401: Not Admin
    
    ProcessInvitation --> ValidateData: Begin Processing
    ValidateData --> SaveInvitation: Valid Data
    ValidateData --> Return422: Invalid Data
    
    SaveInvitation --> Return201: Success
    SaveInvitation --> Return422: DB Error
    
    Return201 --> [*]
    Return401 --> [*]
    Return422 --> [*]
```

---

**Note:** This simplified version maintains business logic integrity while removing authentication complexity for specific use cases where security is handled at different layers.