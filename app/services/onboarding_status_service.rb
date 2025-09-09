# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      step_name = step_name.to_s.underscore

      # Ensure onboarding_status_detail exists
      user.ensure_onboarding_status_detail
      onboarding = user.onboarding_status_detail

      # Store request metadata safely
      onboarding.client_metadata ||= {}
      onboarding.client_metadata['_request_metadata'] =
        request_context.merge('step_completed' => step_name)

      begin
        # Let the model handle completing the step
        onboarding.complete_step!(step_name)

        Rails.logger.info "✅ OnboardingStatusService: Step '#{step_name}' completed for user #{user.auth0_id}"

        { success: true, data: onboarding }

      rescue => e
        Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}"
        { success: false, message: "Failed to complete step", errors: [e.message] }
      end
    end
  end
end
