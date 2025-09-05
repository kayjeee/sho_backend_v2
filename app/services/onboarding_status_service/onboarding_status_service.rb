# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      Rails.logger.info "✅ OnboardingStatusService: Completing step '#{step_name}' for user #{user.auth0_id}"

      begin
        # -----------------------------------
        # 1. Extract only safe fields for persistence
        # -----------------------------------
        safe_metadata = {}
        safe_metadata["grades"]   = metadata["grades"] if metadata["grades"].is_a?(Array)
        safe_metadata["schoolId"] = metadata["schoolId"] if metadata["schoolId"].present?

        # -----------------------------------
        # 2. Log the full metadata + request context (not persisted)
        # -----------------------------------
        Rails.logger.debug "🔍 Raw step metadata: #{metadata.inspect}"
        Rails.logger.debug "🌐 Request context: #{request_context.inspect}"

        # -----------------------------------
        # 3. Persist the safe metadata only (ensure proper BSON serialization)
        # -----------------------------------
        user.onboarding_status ||= {}
        
        # Convert to plain hash to avoid BSON issues
        user.onboarding_status = user.onboarding_status.to_h if user.onboarding_status.respond_to?(:to_h)
        user.onboarding_status[step_name.to_s] = safe_metadata
        
        # Mark the field as dirty to ensure it gets saved
        user.onboarding_status_will_change!
        user.save!

        Rails.logger.info "🎉 Step '#{step_name}' completed for user #{user.auth0_id} with data: #{safe_metadata.inspect}"

        { success: true, message: "Step '#{step_name}' completed", data: safe_metadata }
      rescue => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error completing step: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        { success: false, message: "Unexpected error occurred while completing step", errors: [e.message] }
      end
    end
  end
end