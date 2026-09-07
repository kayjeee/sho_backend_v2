require 'test_helper'

class OnboardingStatusTest < ActiveSupport::TestCase
  setup do
    # Clear Mongoid collections before each test
    Mongoid.purge!

    @school = School.create!(
      schoolName: "Far North Secondary School",
      schoolEmail: "info@farnorth.com"
    )

    @user = User.create!(
      name: "Kagiso Parent",
      email: "kagiso2025@gmail.com",
      auth0_id: "auth0|6929ae9fecac72d4fcc8424d",
      roles: ["default_role", "parent"]
    )
    # Associate user with school
    @user.schools << @school
    @user.save!
  end

  test "role-based step tracking and percentage calculation for parent" do
    # Parent user has 8 steps
    onboarding = @user.onboarding_status
    assert_equal 8, onboarding.total_steps_count
    assert_equal 0.0, onboarding.completion_percentage
    assert_not onboarding.parent_onboarding_completed
    assert_not @user.onboarding_completed

    # Complete 1 step
    OnboardingStatusService.complete_step(@user, "profile_setup")
    @user.reload
    assert_equal 12.5, @user.onboarding_status.completion_percentage
    assert_not @user.onboarding_status.parent_onboarding_completed

    # Complete a second step
    OnboardingStatusService.complete_step(@user, "identity_verification")
    @user.reload
    assert_equal 25.0, @user.onboarding_status.completion_percentage

    # Complete the rest of the parent steps
    parent_steps = OnboardingStatus::PARENT_STEPS
    parent_steps[2..-1].each do |step|
      OnboardingStatusService.complete_step(@user, step)
    end

    @user.reload
    assert_equal 100.0, @user.onboarding_status.completion_percentage
    assert @user.onboarding_status.parent_onboarding_completed
    assert @user.onboarding_completed
  end

  test "role-based branching avoids cross-contamination between admin and parent" do
    admin_user = User.create!(
      name: "Admin User",
      email: "admin@sho.com",
      auth0_id: "auth0|admin123",
      roles: ["admin"]
    )
    admin_user.schools << @school
    admin_user.save!

    # Complete parent steps on admin user should NOT affect admin_onboarding_completed
    OnboardingStatusService.complete_step(admin_user, "profile_setup")
    admin_user.reload
    # admin doesn't track parent steps as part of their percentage
    assert_equal 0.0, admin_user.onboarding_status.completion_percentage
    assert_not admin_user.onboarding_status.admin_onboarding_completed

    # Complete admin steps (including required metadata for create_grades)
    OnboardingStatusService.complete_step(admin_user, "create_grades", { grades: ["Grade 1"], schoolId: @school.id.to_s })
    OnboardingStatusService.complete_step(admin_user, "upload_learners")
    OnboardingStatusService.complete_step(admin_user, "send_invites")
    OnboardingStatusService.complete_step(admin_user, "admin_onboarding")

    admin_user.reload
    assert_equal 100.0, admin_user.onboarding_status.completion_percentage
    assert admin_user.onboarding_status.admin_onboarding_completed
    assert admin_user.onboarding_completed
    assert_not admin_user.onboarding_status.parent_onboarding_completed
  end

  test "idempotency of complete_step calls" do
    # Complete same step twice should not double count or fail
    OnboardingStatusService.complete_step(@user, "profile_setup")
    @user.reload
    assert_equal 12.5, @user.onboarding_status.completion_percentage

    OnboardingStatusService.complete_step(@user, "profile_setup")
    @user.reload
    assert_equal 12.5, @user.onboarding_status.completion_percentage
  end
end
