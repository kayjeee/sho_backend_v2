# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      step_name = step_name.to_s.underscore
      
      if step_name.blank?
        return { 
          success: false, 
          errors: ["Step name is required"], 
          message: "Missing step name parameter" 
        }
      end

      metadata_hash = metadata.respond_to?(:to_unsafe_hash) ? metadata.to_unsafe_hash : metadata.to_h
      
      # Validate metadata for specific steps
      validation_result = validate_step_metadata(step_name, metadata_hash)
      unless validation_result[:valid]
        return { 
          success: false, 
          errors: validation_result[:errors], 
          message: "Invalid step metadata" 
        }
      end

      # Prepare safe metadata - handle both camelCase and snake_case
      safe_metadata = {}
      safe_metadata["grades"] = Array.wrap(metadata_hash["grades"]).compact if metadata_hash["grades"].present?
      
      # Handle both schoolId (camelCase) and school_id (snake_case)
      school_id = metadata_hash["schoolId"] || metadata_hash["school_id"]
      safe_metadata["school_id"] = school_id if school_id.present?

      begin
        # Ensure onboarding_status exists and is properly initialized
        unless user.onboarding_status
          user.build_onboarding_status
        end

        # Complete the step by setting the appropriate field
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
        end

        # Store request metadata in the client_metadata field
        user.onboarding_status.client_metadata ||= {}
        user.onboarding_status.client_metadata["last_request"] = {
          "updated_at" => Time.current.iso8601,
          "user_agent" => request_context[:user_agent],
          "ip_address" => request_context[:ip_address],
          "step_completed" => step_name
        }

        # Store step-specific metadata if provided
        if safe_metadata.any?
          user.onboarding_status.client_metadata["#{step_name}_metadata"] = safe_metadata
        end

        # Save the user which will trigger onboarding status callbacks
        user.save!

        # Handle side effects for specific steps (after save to avoid conflicts)
        create_grades_from_metadata(user, safe_metadata) if step_name == "create_grades"

        Rails.logger.info "✅ OnboardingStatusService: Step '#{step_name}' completed for user #{user.auth0_id}"

        { 
          success: true, 
          data: user.onboarding_status.to_api_hash,
          message: "Step '#{step_name}' completed" 
        }

      rescue => e
        Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}\n#{e.backtrace.join("\n")}"
        { 
          success: false, 
          message: "Unexpected error", 
          errors: [e.message] 
        }
      end
    end

    private

    def validate_step_metadata(step_name, metadata)
      # For now, only validate create_grades step
      return { valid: true, errors: [] } unless step_name.to_s == "create_grades"

      errors = []
      errors << "Grades are required" if metadata["grades"].blank?
      
      # Check for school_id in both camelCase and snake_case formats
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
          grade = Grade.where(name: grade_name, school_id: school_id).first_or_create!(
            grade_level: grade_name.to_s,
            description: "Auto-created during onboarding",
            capacity: 30,
            status: 0,
            min_age: 5,
            max_age: 18,
            fees: 0.0,
            academic_year_start: academic_year_start,
            academic_year_end: academic_year_end,
            curriculum_info: {},
            schedule_info: {}
          )
          Rails.logger.info "✅ Grade '#{grade_name}' ensured for school #{school_id} (id: #{grade.id})"
        rescue => e
          Rails.logger.error "🔥 Error creating grade '#{grade_name}' for school #{school_id}: #{e.message}"
        end
      end
    end
  end
end