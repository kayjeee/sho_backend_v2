# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      step_name = step_name.to_s.underscore
      return { success: false, errors: ["Step name is required"], message: "Missing step name parameter" } if step_name.blank?

      metadata_hash = (metadata.respond_to?(:to_unsafe_hash) ? metadata.to_unsafe_hash : metadata.to_h).with_indifferent_access
      safe_metadata = prepare_safe_metadata(metadata_hash)

      validation_result = validate_step_metadata(step_name, metadata_hash)
      return { success: false, errors: validation_result[:errors], message: "Invalid step metadata" } unless validation_result[:valid]

      # Ensure onboarding_status exists
      user.build_onboarding_status unless user.onboarding_status

      # Update embedded document fields safely
      flip_step(user, step_name)
      update_completed_steps(user, step_name)
      update_client_metadata(user, step_name, safe_metadata, request_context)

      # Recalculate progress metrics and check completion
      user.onboarding_status.calculate_progress_metrics
      user.onboarding_status.auto_complete_if_ready!

      # Persist the embedded onboarding_status directly to trigger callbacks and dirty tracking
      user.onboarding_status.save!

      # Side effects
      run_step_side_effects(user, step_name, safe_metadata)

      Rails.logger.info "✅ OnboardingStatusService: Step '#{step_name}' completed for user #{user.auth0_id}"

      { success: true, data: user.onboarding_status.to_api_hash, message: "Step '#{step_name}' completed" }
    rescue => e
      cleaned_trace = BacktraceCleanerUtil.clean(e.backtrace)
      Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}\n#{cleaned_trace.join("\n")}"
      { success: false, message: "Unexpected error", errors: [e.message] }
    end

    def mark_upload_learners_complete(user, metadata = {}, request_context = {})
      complete_step(user, "upload_learners", metadata, request_context)
    end

    private

    def prepare_safe_metadata(metadata)
      safe_metadata = {}
      safe_metadata["grades"] = Array.wrap(metadata["grades"]).compact if metadata["grades"].present?
      school_id = metadata["schoolId"] || metadata["school_id"]
      safe_metadata["school_id"] = school_id if school_id.present?
      safe_metadata
    end

    # Flip the boolean field in onboarding_status
    def flip_step(user, step_name)
      case step_name
      when "create_grades"
        user.onboarding_status.create_grades = true
      when "upload_learners"
        user.onboarding_status.upload_learners = true
      when "send_invites"
        user.onboarding_status.send_invites = true
      when "admin_onboarding"
        user.onboarding_status.admin_onboarding_completed = true
      when "parent_onboarding"
        user.onboarding_status.parent_onboarding_completed = true
      when "guest_onboarding"
        user.onboarding_status.guest_onboarding_completed = true
      else
        Rails.logger.warn "⚠️ Unknown onboarding step: #{step_name}"
      end
    end

    # Safely push step into completed_steps if not already present
    def update_completed_steps(user, step_name)
      steps = Array(user.onboarding_status.completed_steps).dup
      unless steps.include?(step_name)
        steps << step_name
        user.onboarding_status.completed_steps = steps
      end
    end

    # Store client metadata for the step
    def update_client_metadata(user, step_name, safe_metadata, request_context)
      metadata = (user.onboarding_status.client_metadata || {}).dup
      metadata["last_request"] = {
        "updated_at" => Time.current.iso8601,
        "user_agent" => request_context[:user_agent],
        "ip_address" => request_context[:ip_address],
        "step_completed" => step_name
      }
      metadata["#{step_name}_metadata"] = safe_metadata if safe_metadata.any?

      if step_name == "upload_learners"
        metadata["_request_metadata"] = {
          "updated_at" => Time.current.iso8601,
          "step_completed" => "upload_learners"
        }
      end

      user.onboarding_status.client_metadata = metadata
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
      grades = Array.wrap(metadata["grades"]).compact
      school_id = metadata["school_id"]
      return unless grades.any? && school_id.present?

      current_year = Date.current.year
      academic_year_start = Date.new(current_year, 1, 1)
      academic_year_end = Date.new(current_year, 12, 31)

      grades.each do |grade_name|
        begin
          # Build attributes dynamically based on defined fields in Grade model to prevent schema/branch mismatches
          grade_attrs = { description: "Auto-created during onboarding" }

          if Grade.fields.key?("grade_level")
            grade_attrs[:grade_level] = grade_name.to_s
          elsif Grade.fields.key?("level")
            grade_level_num = grade_name.to_s.gsub(/[^0-9]/, '').to_i
            grade_attrs[:level] = grade_level_num if grade_level_num > 0
          end

          grade_attrs[:capacity] = 30 if Grade.fields.key?("capacity")
          grade_attrs[:status] = 0 if Grade.fields.key?("status")
          grade_attrs[:min_age] = 5 if Grade.fields.key?("min_age")
          grade_attrs[:max_age] = 18 if Grade.fields.key?("max_age")
          grade_attrs[:fees] = 0.0 if Grade.fields.key?("fees")
          grade_attrs[:academic_year_start] = academic_year_start if Grade.fields.key?("academic_year_start")
          grade_attrs[:academic_year_end] = academic_year_end if Grade.fields.key?("academic_year_end")
          grade_attrs[:curriculum_info] = {} if Grade.fields.key?("curriculum_info")
          grade_attrs[:schedule_info] = {} if Grade.fields.key?("schedule_info")
          grade_attrs[:order] = 0 if Grade.fields.key?("order")

          grade = Grade.where(name: grade_name, school_id: school_id).first_or_initialize
          grade.assign_attributes(grade_attrs)
          grade.save!

          Rails.logger.info "✅ Grade '#{grade_name}' ensured for school #{school_id} (id: #{grade.id})"
        rescue => e
          Rails.logger.error "🔥 Error creating grade '#{grade_name}' for school #{school_id}: #{e.message}"
        end
      end
    end
  end
end
