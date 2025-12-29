# app/services/user_services/onboarding_status_service.rb
module UserServices
  class OnboardingStatusService
    Result = Struct.new(:success?, :data, :errors, :message, :metadata, keyword_init: true)

    def initialize(user:, context: {})
      @user = user
      @context = context
    end

    # Class methods for convenient access
    def self.get_status(user:, context: {})
      new(user: user, context: context).get_status
    end

    def self.update_status(user:, updates:, context: {})
      new(user: user, context: context).update_status(updates)
    end

    def self.complete_step(user:, step_name:, metadata: nil, context: {})
      new(user: user, context: context).complete_step(step_name, metadata)
    end

    def self.skip_step(user:, step_name:, reason: nil, context: {})
      new(user: user, context: context).skip_step(step_name, reason)
    end

    def self.complete_onboarding(user:, context: {})
      new(user: user, context: context).complete_onboarding
    end

    def self.reset_onboarding(user:, reset_by: nil, reason: nil, context: {})
      new(user: user, context: context).reset_onboarding(reset_by, reason)
    end

    # Get current onboarding status with comprehensive data
    def get_status
      Rails.logger.debug "📊 OnboardingStatusService: Getting status for user #{@user.auth0_id}"
      
      begin
        @user.ensure_onboarding_status
        
        # Gather additional context data
        context_data = gather_context_data
        
        Result.new(
          success?: true,
          data: @user.onboarding_status.to_api_hash,
          message: "Onboarding status retrieved successfully",
          metadata: {
            context: context_data,
            retrieved_at: Time.current.iso8601,
            user_roles: @user.roles,
            school_count: @user.schools.count
          }
        )
        
      rescue StandardError => e
        Rails.logger.error "❌ OnboardingStatusService: Error getting status: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Failed to retrieve onboarding status"
        )
      end
    end

    # Update onboarding status with validation and business logic
    def update_status(updates)
      Rails.logger.debug "🔄 OnboardingStatusService: Updating status for user #{@user.auth0_id} with #{updates.inspect}"
      
      begin
        @user.ensure_onboarding_status
        
        # Validate updates before applying
        validation_result = validate_updates(updates)
        return validation_result unless validation_result.success?
        
        # Store original state for rollback if needed
        original_state = @user.onboarding_status.to_api_hash
        
        # Apply updates with transaction-like behavior
        @user.onboarding_status.assign_attributes_from_api(updates)
        @user.onboarding_status.auto_complete_if_ready!
        
        if @user.onboarding_status.save
          Rails.logger.info "✅ OnboardingStatusService: Status updated for user #{@user.auth0_id}"
          
          # Track the changes for analytics
          track_status_changes(original_state, @user.onboarding_status.to_api_hash)
          
          Result.new(
            success?: true,
            data: @user.onboarding_status.to_api_hash,
            message: "Onboarding status updated successfully",
            metadata: {
              updated_at: Time.current.iso8601,
              changes_applied: calculate_changes(original_state, @user.onboarding_status.to_api_hash)
            }
          )
        else
          Rails.logger.error "❌ OnboardingStatusService: Failed to update status. Errors: #{@user.onboarding_status.errors.full_messages.join(', ')}"
          Result.new(
            success?: false,
            errors: @user.onboarding_status.errors.full_messages,
            message: "Failed to update onboarding status"
          )
        end
        
      rescue StandardError => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error updating status: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Unexpected error occurred while updating onboarding status"
        )
      end
    end

    # Complete a specific step with comprehensive validation and side effects
    def complete_step(step_name, metadata = nil)
      metadata ||= {}
      Rails.logger.debug "✅ OnboardingStatusService: Completing step '#{step_name}' for user #{@user.auth0_id}"

      # Auto-infer school_id for create_grades if user has exactly one school
      if step_name == 'create_grades' && metadata['school_id'].blank?
        if @user.schools.count == 1
          metadata['school_id'] = @user.schools.first.id.to_s
          Rails.logger.info "  -> Inferred school_id: #{metadata['school_id']} for user #{@user.auth0_id}"
        end
      end
      
      begin
        @user.ensure_onboarding_status
        
        # Validate step name and prerequisites
        validation_result = validate_step_completion(step_name)
        return validation_result unless validation_result.success?
        
        # Store completion metadata
        completion_metadata = {
          completed_at: Time.current.iso8601,
          context: @context,
          user_provided_metadata: metadata
        }
        
        # Complete the step
        @user.complete_onboarding_step!(step_name, metadata: completion_metadata)
        
        # Handle step-specific side effects
        handle_step_side_effects(step_name, metadata)
        
        Rails.logger.info "🎯 OnboardingStatusService: Step '#{step_name}' completed for user #{@user.auth0_id}"
        
        Result.new(
          success?: true,
          data: @user.onboarding_status.to_api_hash,
          message: "Step '#{step_name}' completed successfully",
          metadata: {
            step_completed: step_name,
            completion_metadata: completion_metadata,
            next_step: @user.onboarding_status.next_step
          }
        )
        
      rescue ArgumentError => e
        Rails.logger.warn "⚠️ OnboardingStatusService: Step completion validation failed: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Step completion validation failed"
        )
      rescue StandardError => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error completing step: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Unexpected error occurred while completing step"
        )
      end
    end

    # Skip a specific step with reason tracking
    def skip_step(step_name, reason)
      Rails.logger.debug "⏭️ OnboardingStatusService: Skipping step '#{step_name}' for user #{@user.auth0_id}"
      
      begin
        @user.ensure_onboarding_status
        
        # Validate that step can be skipped
        validation_result = validate_step_skip(step_name)
        return validation_result unless validation_result.success?
        
        # Skip the step with metadata
        skip_metadata = {
          reason: reason,
          context: @context,
          skipped_at: Time.current.iso8601
        }
        
        @user.skip_onboarding_step!(step_name, reason: reason, metadata: skip_metadata)
        
        Rails.logger.info "⏭️ OnboardingStatusService: Step '#{step_name}' skipped for user #{@user.auth0_id}"
        
        Result.new(
          success?: true,
          data: @user.onboarding_status.to_api_hash,
          message: "Step '#{step_name}' skipped successfully",
          metadata: {
            step_skipped: step_name,
            skip_reason: reason,
            next_step: @user.onboarding_status.next_step
          }
        )
        
      rescue StandardError => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error skipping step: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Unexpected error occurred while skipping step"
        )
      end
    end

    # Mark entire onboarding as complete with comprehensive finalization
    def complete_onboarding
      Rails.logger.debug "🏁 OnboardingStatusService: Completing onboarding for user #{@user.auth0_id}"
      
      begin
        @user.ensure_onboarding_status
        
        # Validate that onboarding can be completed
        validation_result = validate_onboarding_completion
        return validation_result unless validation_result.success?
        
        onboarding = @user.onboarding_status
        
        # Force completion of all required steps
        complete_all_required_steps(onboarding)
        
        # Mark as completed
        onboarding.completed = true
        onboarding.completed_at = Time.current
        onboarding.current_step = nil
        
        # Store completion metadata
        onboarding.client_metadata['completion_context'] = {
          completed_by: 'service',
          completion_method: 'force_complete',
          context: @context,
          completed_at: Time.current.iso8601
        }
        
        if onboarding.save
          # Handle completion side effects
          handle_onboarding_completion_side_effects
          
          Rails.logger.info "🎉 OnboardingStatusService: Onboarding completed for user #{@user.auth0_id}"
          
          Result.new(
            success?: true,
            data: onboarding.to_api_hash,
            message: "Onboarding completed successfully",
            metadata: {
              completion_method: 'force_complete',
              completed_at: Time.current.iso8601,
              total_time: @user.calculate_time_to_complete
            }
          )
        else
          Rails.logger.error "❌ OnboardingStatusService: Failed to complete onboarding. Errors: #{onboarding.errors.full_messages.join(', ')}"
          Result.new(
            success?: false,
            errors: onboarding.errors.full_messages,
            message: "Failed to complete onboarding"
          )
        end
        
      rescue StandardError => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error completing onboarding: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Unexpected error occurred while completing onboarding"
        )
      end
    end

    # Reset onboarding status with comprehensive audit trail
    def reset_onboarding(reset_by, reason)
      Rails.logger.debug "🔄 OnboardingStatusService: Resetting onboarding for user #{@user.auth0_id}"
      
      begin
        @user.ensure_onboarding_status
        
        # Store pre-reset state for audit
        pre_reset_state = @user.onboarding_status.to_api_hash
        
        # Reset with audit information
        @user.reset_onboarding!(reset_by: reset_by, reason: reason)
        
        # Log the reset for audit purposes
        log_onboarding_reset(pre_reset_state, reset_by, reason)
        
        Rails.logger.info "🔄 OnboardingStatusService: Onboarding reset for user #{@user.auth0_id}"
        
        Result.new(
          success?: true,
          data: @user.onboarding_status.to_api_hash,
          message: "Onboarding reset successfully",
          metadata: {
            reset_by: reset_by,
            reset_reason: reason,
            reset_at: Time.current.iso8601,
            pre_reset_state: pre_reset_state
          }
        )
        
      rescue StandardError => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error resetting onboarding: #{e.message}"
        Result.new(
          success?: false,
          errors: [e.message],
          message: "Unexpected error occurred while resetting onboarding"
        )
      end
    end

    private

    # Gather contextual data for enhanced status information
    def gather_context_data
      {
        user_schools_count: @user.schools.count,
        user_grades_count: @user.created_grades.count,
        user_learners_count: @user.created_learners.count,
        user_roles: @user.roles,
        account_age_days: ((Time.current - @user.created_at) / 1.day).to_i,
        last_login: @user.last_login&.iso8601
      }
    end

    # Validate update parameters with comprehensive checks
    def validate_updates(updates)
      return Result.new(
        success?: false, 
        errors: ["Updates cannot be empty"], 
        message: "No updates provided"
      ) if updates.blank?
      
      # Check for invalid keys
      valid_keys = %w[createGrades uploadLearners sendInvites adminOnboardingCompleted parentOnboardingCompleted guestOnboardingCompleted currentStep skippedSteps]
      invalid_keys = updates.keys - valid_keys
      
      if invalid_keys.any?
        return Result.new(
          success?: false,
          errors: ["Invalid keys: #{invalid_keys.join(', ')}"],
          message: "Invalid update parameters provided"
        )
      end
      
      # Validate step dependencies
      dependency_validation = validate_step_dependencies(updates)
      return dependency_validation unless dependency_validation.success?
      
      # Validate role-specific updates
      role_validation = validate_role_specific_updates(updates)
      return role_validation unless role_validation.success?
      
      Result.new(success?: true, message: "Validation passed")
    end

    # Validate step dependencies in updates
    def validate_step_dependencies(updates)
      current_status = @user.onboarding_status
      
      if updates['uploadLearners'] == true && 
         !current_status.create_grades && 
         updates['createGrades'] != true
        return Result.new(
          success?: false,
          errors: ["Cannot complete uploadLearners before createGrades"],
          message: "Step dependency validation failed"
        )
      end
      
      if updates['sendInvites'] == true && 
         !current_status.upload_learners && 
         updates['uploadLearners'] != true
        return Result.new(
          success?: false,
          errors: ["Cannot complete sendInvites before uploadLearners"],
          message: "Step dependency validation failed"
        )
      end
      
      Result.new(success?: true, message: "Dependency validation passed")
    end

    # Validate role-specific updates
    def validate_role_specific_updates(updates)
      user_roles = @user.roles || []
      
      if updates['adminOnboardingCompleted'] == true && !user_roles.include?('admin')
        return Result.new(
          success?: false,
          errors: ["Cannot complete admin onboarding for non-admin user"],
          message: "Role validation failed"
        )
      end
      
      if updates['parentOnboardingCompleted'] == true && !user_roles.include?('parent')
        return Result.new(
          success?: false,
          errors: ["Cannot complete parent onboarding for non-parent user"],
          message: "Role validation failed"
        )
      end
      
      if updates['guestOnboardingCompleted'] == true && !user_roles.include?('guest')
        return Result.new(
          success?: false,
          errors: ["Cannot complete guest onboarding for non-guest user"],
          message: "Role validation failed"
        )
      end
      
      Result.new(success?: true, message: "Role validation passed")
    end

    # Validate step completion prerequisites
    def validate_step_completion(step_name)
      valid_steps = %w[create_grades upload_learners send_invites admin_onboarding parent_onboarding guest_onboarding]
      
      unless valid_steps.include?(step_name.to_s)
        return Result.new(
          success?: false,
          errors: ["Invalid step name: #{step_name}"],
          message: "Invalid step name provided"
        )
      end
      
      # Check role-specific step validation
      if step_name.to_s.include?('_onboarding')
        role_validation = validate_role_specific_step(step_name)
        return role_validation unless role_validation.success?
      end
      
      Result.new(success?: true, message: "Step validation passed")
    end

    # Validate role-specific step completion
    def validate_role_specific_step(step_name)
      user_roles = @user.roles || []
      
      case step_name.to_s
      when 'admin_onboarding'
        unless user_roles.include?('admin')
          return Result.new(
            success?: false,
            errors: ["User does not have admin role"],
            message: "Role validation failed for admin onboarding"
          )
        end
      when 'parent_onboarding'
        unless user_roles.include?('parent')
          return Result.new(
            success?: false,
            errors: ["User does not have parent role"],
            message: "Role validation failed for parent onboarding"
          )
        end
      when 'guest_onboarding'
        unless user_roles.include?('guest')
          return Result.new(
            success?: false,
            errors: ["User does not have guest role"],
            message: "Role validation failed for guest onboarding"
          )
        end
      end
      
      Result.new(success?: true, message: "Role-specific step validation passed")
    end

    # Validate step skip operation
    def validate_step_skip(step_name)
      # Most steps can be skipped, but we might want to restrict certain critical steps
      restricted_steps = [] # Add any steps that cannot be skipped
      
      if restricted_steps.include?(step_name.to_s)
        return Result.new(
          success?: false,
          errors: ["Step '#{step_name}' cannot be skipped"],
          message: "Step skip validation failed"
        )
      end
      
      Result.new(success?: true, message: "Step skip validation passed")
    end

    # Validate onboarding completion
    def validate_onboarding_completion
      # Check if user has minimum required data to complete onboarding
      if @user.schools.empty?
        return Result.new(
          success?: false,
          errors: ["User must be associated with at least one school"],
          message: "Onboarding completion validation failed"
        )
      end
      
      Result.new(success?: true, message: "Onboarding completion validation passed")
    end

    # Complete all required steps for force completion
    def complete_all_required_steps(onboarding)
      onboarding.create_grades = true
      onboarding.upload_learners = true
      onboarding.send_invites = true
      
      # Complete role-specific onboarding based on user roles
      user_roles = @user.roles || []
      onboarding.admin_onboarding_completed = true if user_roles.include?('admin')
      onboarding.parent_onboarding_completed = true if user_roles.include?('parent')
      onboarding.guest_onboarding_completed = true if user_roles.include?('guest')
    end

    # Handle step-specific side effects
    def handle_step_side_effects(step_name, metadata)
      case step_name.to_s
      when 'create_grades'
        # Could trigger grade creation analytics, notifications, etc.
        Rails.logger.debug "🎯 Handling create_grades side effects"
      when 'upload_learners'
        # Could trigger learner import analytics, welcome emails, etc.
        Rails.logger.debug "👥 Handling upload_learners side effects"
      when 'send_invites'
        # Could trigger invitation analytics, follow-up scheduling, etc.
        Rails.logger.debug "📧 Handling send_invites side effects"
      end
    end

    # Handle onboarding completion side effects
    def handle_onboarding_completion_side_effects
      # Send completion notification
      # OnboardingCompletionNotificationJob.perform_async(@user.id)
      
      # Update user permissions or access levels
      # UserPermissionUpdateJob.perform_async(@user.id)
      
      # Trigger analytics event
      # AnalyticsService.track_onboarding_completion(@user)
      
      Rails.logger.debug "🎉 Handling onboarding completion side effects for user #{@user.auth0_id}"
    end

    # Track status changes for analytics
    def track_status_changes(original_state, new_state)
      changes = calculate_changes(original_state, new_state)
      
      if changes.any?
        Rails.logger.debug "📊 Onboarding status changes for user #{@user.auth0_id}: #{changes.inspect}"
        # AnalyticsService.track_onboarding_status_changes(@user, changes)
      end
    end

    # Calculate changes between two states
    def calculate_changes(original_state, new_state)
      changes = {}
      
      new_state.each do |key, value|
        if original_state[key] != value
          changes[key] = {
            from: original_state[key],
            to: value
          }
        end
      end
      
      changes
    end

    # Log onboarding reset for audit purposes
    def log_onboarding_reset(pre_reset_state, reset_by, reason)
      audit_data = {
        user_id: @user.auth0_id,
        reset_by: reset_by,
        reset_reason: reason,
        reset_at: Time.current.iso8601,
        pre_reset_completion_percentage: pre_reset_state[:progress][:percentage],
        pre_reset_completed_steps: pre_reset_state[:progress][:stepsCompleted],
        context: @context
      }
      
      Rails.logger.info "🔍 Onboarding reset audit: #{audit_data.to_json}"
      # AuditLogService.log_onboarding_reset(audit_data)
    end
  end
end