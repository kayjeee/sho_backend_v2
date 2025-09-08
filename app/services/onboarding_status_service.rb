# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    # Complete a specific onboarding step safely
    def complete_step(user, step_name, metadata = {}, request_context = {})
      step_name = step_name.to_s.underscore

      # Initialize onboarding_status if missing
      unless user.onboarding_status
        user.build_onboarding_status
      end

      onboarding = user.onboarding_status

      # Store request metadata safely
      onboarding.client_metadata ||= {}
      onboarding.client_metadata['_request_metadata'] = request_context.merge('step_completed' => step_name)

      # Complete the step
      begin
        case step_name
        when 'create_grades'
          onboarding.create_grades = true
        when 'upload_learners'
          onboarding.upload_learners = true
        when 'send_invites'
          onboarding.send_invites = true
        when 'admin_onboarding'
          onboarding.admin_onboarding_completed = true
        when 'parent_onboarding'
          onboarding.parent_onboarding_completed = true
        when 'guest_onboarding'
          onboarding.guest_onboarding_completed = true
        else
          raise ArgumentError, "Unknown step: #{step_name}"
        end

        # Update current_step to next step
        onboarding.current_step = onboarding.next_step

        # Recalculate progress metrics
        onboarding.calculate_progress_metrics
        onboarding.set_last_updated
        onboarding.update_version

        # Auto-complete if all steps done
        onboarding.auto_complete_if_ready!

        onboarding.save!  # Save safely

        Rails.logger.info "✅ OnboardingStatusService: Step '#{step_name}' completed for user #{user.auth0_id}"

        { success: true, data: onboarding }

      rescue => e
        Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}"
        { success: false, error: e.message }
      end
    end
  end
end
