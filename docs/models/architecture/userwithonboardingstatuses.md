I've created a complete User model that integrates all the onboarding functionality with your existing grade-related associations and school management methods. Here are the key features of this comprehensive implementation:
Key Components Added:
1. Onboarding Integration

embeds_one :onboarding_status association
Automatic initialization callbacks (after_initialize, after_create)
Lazy loading with ensure_onboarding_status

2. Role-Based Onboarding Configuration

Different step counts based on user roles (admin: 4 steps, parent/guest: 1 step, default: 3 steps)
Context-aware initialization tracking
Role-specific completion logic

3. Comprehensive Onboarding Methods

complete_onboarding_step! - Complete steps with metadata tracking
skip_onboarding_step! - Skip steps with reason tracking
reset_onboarding! - Reset with audit trail
Progress tracking and analytics methods

4. Enhanced API Integration

to_api_hash includes onboarding status in camelCase
Support for both snake_case and camelCase input
Comprehensive error handling

5. Admin Dashboard Support

Bulk operations (bulk_update_onboarding_status)
User filtering by onboarding status
Statistics and analytics methods

6. Preserved Existing Functionality

All grade-related associations and methods
School management (add_school, remove_school)
Validation and callback logic

7. New Utility Methods

Role checking methods (admin?, parent?, guest?)
Display name formatting
Enhanced logging and error handling

8. Performance Optimizations

Strategic indexing for onboarding queries
Efficient scopes for filtering users
Lazy initialization to avoid unnecessary database calls

The model maintains backward compatibility while adding comprehensive onboarding functionality that integrates seamlessly with your existing grade and school management systems. The implementation includes proper error handling, logging, and audit trails for production use.