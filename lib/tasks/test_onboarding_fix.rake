namespace :onboarding do
  desc "Run a comprehensive, idempotent test for the onboarding fixes"
  task test_fix: :environment do
    puts "=== COMPREHENSIVE ONBOARDING FIX TEST ===\n"

    # --- Cleanup ---
    puts "--- Cleaning up previous test users ---"
    test_emails = [
      "admin_test_fix@example.com",
      "parent_test_fix@example.com",
      "mixed@example.com",
      "norole@example.com",
      "multi@example.com"
    ]
    User.where(:email.in => test_emails).destroy_all
    puts "Cleanup complete.\n"

    # 1. Test Admin User Creation
    puts "1. Testing Admin User Creation"
    admin_user = User.create!(
      name: "Test Admin",
      email: "admin_test_fix@example.com",
      auth0_id: "admin_test_fix",
      roles: ["admin"]
    )

    puts "  ✅ Admin created: #{admin_user.email}"
    puts "  Roles: #{admin_user.roles}"
    puts "  Is admin? #{admin_user.admin?}"
    puts "  Total steps: #{admin_user.onboarding_status.total_steps_count} (should be 4)"
    puts "  Current step: '#{admin_user.onboarding_status.current_step}' (should be 'create_grades')"
    puts "  Completion %: #{admin_user.onboarding_status.completion_percentage}% (should be 0%)"
    puts "  Started at is present? #{admin_user.onboarding_status.started_at.present?}"
    puts ""

    # 2. Test Parent User Creation
    puts "2. Testing Parent User Creation"
    parent_user = User.create!(
      name: "Test Parent",
      email: "parent_test_fix@example.com",
      auth0_id: "parent_test_fix",
      roles: ["parent"]
    )

    puts "  ✅ Parent created: #{parent_user.email}"
    puts "  Roles: #{parent_user.roles}"
    puts "  Is parent? #{parent_user.parent?}"
    puts "  Total steps: #{parent_user.onboarding_status.total_steps_count} (should be 1)"
    puts "  Current step: '#{parent_user.onboarding_status.current_step}' (should be 'parent_onboarding')"
    puts "  Completion %: #{parent_user.onboarding_status.completion_percentage}% (should be 0%)"
    puts ""

    # 3. Test Completion Percentage Calculation
    puts "3. Testing Completion Percentage Calculation"

    # Complete first step for admin
    admin_user.onboarding_status.create_grades = true
    admin_user.save! # Save the parent user to trigger embedded callbacks

    puts "  Admin completed create_grades"
    puts "  Completion %: #{admin_user.onboarding_status.completion_percentage}% (should be 25%)"

    # Complete second step
    admin_user.onboarding_status.upload_learners = true
    admin_user.save!

    puts "  Admin completed upload_learners"
    puts "  Completion %: #{admin_user.onboarding_status.completion_percentage}% (should be 50%)"

    # Complete parent onboarding
    parent_user.onboarding_status.parent_onboarding_completed = true
    parent_user.save!

    puts "  Parent completed parent_onboarding"
    puts "  Completion %: #{parent_user.onboarding_status.completion_percentage}% (should be 100%)"
    puts "  Completed flag: #{parent_user.onboarding_status.completed} (should be true)"
    puts ""

    # 4. Test Case-Insensitive Roles
    puts "4. Testing Case-Insensitive Roles"
    mixed_case_user = User.create!(
      name: "Mixed Case User",
      email: "mixed@example.com",
      auth0_id: "mixed_case",
      roles: ["Admin", "Parent", "GUEST"]
    )

    puts "  User created with mixed case roles: ['Admin', 'Parent', 'GUEST']"
    puts "  Stored roles (should be lowercase): #{mixed_case_user.roles}"
    puts "  Is admin? #{mixed_case_user.admin?} (should be true)"
    puts "  Is parent? #{mixed_case_user.parent?} (should be true)"
    puts "  Is guest? #{mixed_case_user.guest?} (should be true)"
    puts "  Has role 'ADMIN'? #{mixed_case_user.has_role?('ADMIN')} (should be true)"
    puts ""

    # 5. Test Edge Cases
    puts "5. Testing Edge Cases"

    # User with no roles
    no_role_user = User.create!(
      name: "No Role User",
      email: "norole@example.com",
      auth0_id: "norole",
      roles: []
    )

    puts "  No role user created"
    puts "  Total steps: #{no_role_user.onboarding_status.total_steps_count} (should be 3)"
    puts "  Current step: '#{no_role_user.onboarding_status.current_step}' (should be 'create_grades')"
    puts ""

    # User with multiple roles (admin + parent)
    multi_role_user = User.create!(
      name: "Multi Role User",
      email: "multi@example.com",
      auth0_id: "multi",
      roles: ["admin", "parent"]
    )

    puts "  Multi-role user (admin + parent)"
    puts "  Total steps: #{multi_role_user.onboarding_status.total_steps_count} (admin should win = 4)"
    puts "  Current step: '#{multi_role_user.onboarding_status.current_step}' (should be 'create_grades')"
    puts ""

    puts "=== TEST COMPLETE ==="
  end
end
