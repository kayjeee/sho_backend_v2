# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      step_name = step_name.to_s.strip
      return { success: false, errors: ["Step name is required"], message: "Missing step name parameter" } if step_name.blank?

      # Ensure onboarding_status exists
      user.build_onboarding_status unless user.onboarding_status

      metadata_hash = metadata.respond_to?(:to_unsafe_hash) ? metadata.to_unsafe_hash : metadata.to_h
      safe_metadata = prepare_safe_metadata(metadata_hash)

      # ── PARENT FLOW ──────────────────────────────────────────
      # If this step name matches the canonical parent list, use the
      # dedicated parent method and skip the legacy admin logic entirely.
      if OnboardingStatus::PARENT_STEPS.include?(step_name.upcase)
        return handle_parent_step(user, step_name.upcase, safe_metadata, request_context)
      end
      # ── END PARENT FLOW ──────────────────────────────────────

      # Legacy admin / guest path (unchanged)
      step_name_underscored = step_name.underscore

      validation_result = validate_step_metadata(step_name_underscored, metadata_hash)
      return { success: false, errors: validation_result[:errors], message: "Invalid step metadata" } unless validation_result[:valid]

      flip_step(user, step_name_underscored)
      update_completed_steps(user, step_name_underscored)
      update_client_metadata(user, step_name_underscored, safe_metadata, request_context)

      user.save!
      run_step_side_effects(user, step_name_underscored, safe_metadata)

      Rails.logger.info "✅ OnboardingStatusService: Step '#{step_name_underscored}' completed for user #{user.auth0_id}"
      { success: true, data: user.onboarding_status.to_api_hash, message: "Step '#{step_name_underscored}' completed" }

    rescue => e
      Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { success: false, message: "Unexpected error", errors: [e.message] }
    end

    def mark_upload_learners_complete(user, metadata = {}, request_context = {})
      complete_step(user, "upload_learners", metadata, request_context)
    end

    private

    # ── Parent step handler ──────────────────────────────────
    def handle_parent_step(user, step_name, safe_metadata, request_context)
      # Store per-step metadata for auditing
      user.onboarding_status.client_metadata ||= {}
      user.onboarding_status.client_metadata["#{step_name.downcase}_metadata"] = safe_metadata if safe_metadata.any?
      user.onboarding_status.client_metadata["#{step_name.downcase}_completed_at"] = Time.current.iso8601
      user.onboarding_status.client_metadata["last_request"] = {
        "updated_at"     => Time.current.iso8601,
        "user_agent"     => request_context[:user_agent],
        "ip_address"     => request_context[:ip_address],
        "step_completed" => step_name
      }

      # This does the actual write + save
      user.onboarding_status.mark_parent_step_complete!(step_name)

      Rails.logger.info "✅ OnboardingStatusService: Parent step '#{step_name}' completed for user #{user.auth0_id} " \
                        "(next: #{user.onboarding_status.next_parent_step})"

      {
        success: true,
        data: user.onboarding_status.to_api_hash,
        message: "Step '#{step_name}' completed"
      }
    rescue => e
      Rails.logger.error "❌ Failed to complete parent step '#{step_name}': #{e.message}"
      { success: false, message: "Failed to complete step", errors: [e.message] }
    end
    # ── End parent step handler ──────────────────────────────

    def prepare_safe_metadata(metadata)
      safe_metadata = {}
      safe_metadata["grades"]    = Array.wrap(metadata["grades"]).compact if metadata["grades"].present?
      school_id                  = metadata["schoolId"] || metadata["school_id"]
      safe_metadata["school_id"] = school_id if school_id.present?
      # Pass through any parent-specific keys
      %w[tier billingCycle transaction_id status subscription_tier
         subscription_billing_cycle amount socialShares].each do |key|
        safe_metadata[key] = metadata[key] if metadata[key].present?
      end
      safe_metadata
    end

    def flip_step(user, step_name)
      case step_name
      when "create_grades"    then user.onboarding_status.set(create_grades: true)
      when "upload_learners"  then user.onboarding_status.set(upload_learners: true)
      when "send_invites"     then user.onboarding_status.set(send_invites: true)
      when "admin_onboarding" then user.onboarding_status.set(admin_onboarding_completed: true)
      when "parent_onboarding"then user.onboarding_status.set(parent_onboarding_completed: true)
      when "guest_onboarding" then user.onboarding_status.set(guest_onboarding_completed: true)
      else
        Rails.logger.warn "⚠️ Unknown onboarding step: #{step_name}"
      end
    end

    def update_completed_steps(user, step_name)
      steps = Array(user.onboarding_status.completed_steps)
      return if steps.include?(step_name)
      steps << step_name
      user.onboarding_status.set(completed_steps: steps)
    end

    def update_client_metadata(user, step_name, safe_metadata, request_context)
      user.onboarding_status.client_metadata ||= {}
      user.onboarding_status.client_metadata["last_request"] = {
        "updated_at"     => Time.current.iso8601,
        "user_agent"     => request_context[:user_agent],
        "ip_address"     => request_context[:ip_address],
        "step_completed" => step_name
      }
      user.onboarding_status.client_metadata["#{step_name}_metadata"] = safe_metadata if safe_metadata.any?
    end

    def run_step_side_effects(user, step_name, safe_metadata)
      if ["create_grades", "upload_learners"].include?(step_name)
        create_grades_from_metadata(user, safe_metadata)
      end
    end

    def validate_step_metadata(step_name, metadata)
      return { valid: true, errors: [] } unless ["create_grades"].include?(step_name)
      errors = []
      errors << "Grades are required" if metadata["grades"].blank?
      school_id = metadata["schoolId"] || metadata["school_id"]
      errors << "School ID is required" if school_id.blank?
      { valid: errors.empty?, errors: errors }
    end

    def create_grades_from_metadata(user, metadata)
      grades   = Array.wrap(metadata["grades"]).compact
      school_id = metadata["school_id"]
      return unless grades.any? && school_id.present?

      current_year          = Date.current.year
      academic_year_start   = Date.new(current_year, 1, 1)
      academic_year_end     = Date.new(current_year, 12, 31)

      grades.each do |grade_name|
        begin
          grade = Grade.where(name: grade_name, school_id: school_id).first_or_create!(
            grade_level: grade_name.to_s,
            description: "Auto-created during onboarding",
            capacity: 30, status: 0, min_age: 5, max_age: 18, fees: 0.0,
            academic_year_start: academic_year_start,
            academic_year_end: academic_year_end,
            curriculum_info: {}, schedule_info: {}
          )
          Rails.logger.info "✅ Grade '#{grade_name}' ensured for school #{school_id} (id: #{grade.id})"
        rescue => e
          Rails.logger.error "🔥 Error creating grade '#{grade_name}' for school #{school_id}: #{e.message}"
        end
      end
    end
  end
end