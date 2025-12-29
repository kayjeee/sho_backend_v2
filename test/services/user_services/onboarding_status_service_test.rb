# test/services/user_services/onboarding_status_service_test.rb
require 'test_helper'
require 'mocha/minitest'

module UserServices
  class OnboardingStatusServiceTest < ActiveSupport::TestCase
    def setup
      # Basic setup for all tests
      @school1 = schools(:school_one)
      @school2 = schools(:school_two)
      @admin_user_single_school = users(:admin_user)
      @admin_user_multi_school = users(:staff_user)

      # Ensure users have the correct roles and school associations
      @admin_user_single_school.roles = ['admin']
      @admin_user_single_school.schools = [@school1]
      @admin_user_single_school.save!

      @admin_user_multi_school.roles = ['admin']
      @admin_user_multi_school.schools = [@school1, @school2]
      @admin_user_multi_school.save!

      # Ensure onboarding status is initialized
      @admin_user_single_school.ensure_onboarding_status
      @admin_user_multi_school.ensure_onboarding_status
    end

    test 'complete_step should infer school_id for user with a single school' do
      # Mock the underlying model method to isolate the service logic
      mock_user = @admin_user_single_school
      mock_user.expects(:complete_onboarding_step!).with do |step_name, metadata|
        step_name == 'create_grades' && metadata[:user_provided_metadata]['school_id'] == @school1.id.to_s
      end.once

      service = OnboardingStatusService.new(user: mock_user)
      result = service.complete_step('create_grades') # school_id is intentionally omitted

      assert result.success?, "Service call should be successful"
      assert_equal "Step 'create_grades' completed successfully", result.message
    end

    test 'complete_step should NOT infer school_id for user with multiple schools' do
      # For a user with multiple schools, the underlying method should fail if school_id is missing
      # The service calls `validate_step_completion` which is private, but the public effect is
      # that `complete_onboarding_step!` is called, which in turn calls the validator in the model.
      # The model `OnboardingStepValidator` should raise an ArgumentError.

      service = OnboardingStatusService.new(user: @admin_user_multi_school)

      # We expect an ArgumentError from the model's validation when metadata is missing
      # Let's verify the service catches it and returns a failure result.
      result = service.complete_step('create_grades', {}) # Empty metadata

      assert_not result.success?, "Service call should fail for multi-school user without school_id"
      assert_includes result.errors, "School ID is required for this step"
    end

    test 'complete_step should succeed for multi-school user when school_id is provided' do
      mock_user = @admin_user_multi_school
      mock_user.expects(:complete_onboarding_step!).with do |step_name, metadata|
        step_name == 'create_grades' && metadata[:user_provided_metadata]['school_id'] == @school2.id.to_s
      end.once

      service = OnboardingStatusService.new(user: mock_user)
      result = service.complete_step('create_grades', { 'school_id' => @school2.id.to_s })

      assert result.success?, "Service call should be successful with explicit school_id"
      assert_equal "Step 'create_grades' completed successfully", result.message
    end

    test 'complete_step should fail gracefully with invalid step name' do
      service = OnboardingStatusService.new(user: @admin_user_single_school)
      result = service.complete_step('an_invalid_step')

      assert_not result.success?, "Service should fail with invalid step name"
      assert_includes result.errors.first, "Invalid step name"
    end
  end
end
