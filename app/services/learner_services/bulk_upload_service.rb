# app/services/onboarding_status_service.rb
class OnboardingStatusService
  VALID_STEPS = %w[
    upload_learners
    create_assessment
    send_notifications
    setup_classes
    configure_settings
  ].freeze

  class << self
    # Enhanced method with better error handling and context support
    def mark_upload_learners_complete(user, context = {})
      return false unless user&.persisted?
      
      mark_step_complete(user, "upload_learners", context)
    end

    # Generic method for marking any onboarding step complete
    def mark_step_complete(user, step_name, context = {})
      return false unless user&.persisted?
      return false unless VALID_STEPS.include?(step_name.to_s)

      begin
        Rails.logger.info "📌 Starting onboarding step completion: #{step_name} for user #{user.id}"
        
        # Use a single atomic operation where possible
        update_operations = build_update_operations(step_name, context)
        
        # Perform the update
        result = user.collection.find_one_and_update(
          { "_id" => user.id },
          update_operations,
          return_document: :after
        )

        if result
          Rails.logger.info "✅ User #{user.id} onboarding: #{step_name} completed successfully"
          true
        else
          Rails.logger.error "❌ Failed to update onboarding status for user #{user.id}"
          false
        end

      rescue => e
        Rails.logger.error "❌ Onboarding update error for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
        false
      end
    end

    # Check if a specific step is completed
    def step_completed?(user, step_name)
      return false unless user&.persisted?
      return false unless VALID_STEPS.include?(step_name.to_s)

      user.onboarding_status&.dig("completed_steps")&.include?(step_name.to_s) || false
    end

    # Get completion percentage
    def completion_percentage(user)
      return 0 unless user&.persisted?

      completed_steps = user.onboarding_status&.dig("completed_steps") || []
      completed_count = (completed_steps & VALID_STEPS).size
      
      ((completed_count.to_f / VALID_STEPS.size) * 100).round(2)
    end

    # Get next incomplete step
    def next_step(user)
      return VALID_STEPS.first unless user&.persisted?

      completed_steps = user.onboarding_status&.dig("completed_steps") || []
      VALID_STEPS.find { |step| !completed_steps.include?(step) }
    end

    # Reset onboarding status (useful for testing or re-onboarding)
    def reset_onboarding(user)
      return false unless user&.persisted?

      begin
        user.unset("onboarding_status")
        Rails.logger.info "🔄 Onboarding status reset for user #{user.id}"
        true
      rescue => e
        Rails.logger.error "❌ Failed to reset onboarding for user #{user.id}: #{e.message}"
        false
      end
    end

    # Bulk mark multiple steps as complete (useful for data migrations)
    def mark_multiple_steps_complete(user, steps, context = {})
      return false unless user&.persisted?

      valid_steps = steps.select { |step| VALID_STEPS.include?(step.to_s) }
      return false if valid_steps.empty?

      begin
        update_operations = {
          "$addToSet" => {
            "onboarding_status.completed_steps" => { "$each" => valid_steps.map(&:to_s) }
          },
          "$set" => {}
        }

        # Set individual step flags
        valid_steps.each do |step|
          update_operations["$set"]["onboarding_status.#{step}"] = true
        end

        # Add metadata
        update_operations["$set"]["onboarding_status.client_metadata.last_bulk_update"] = build_metadata(context.merge(
          step_completed: "bulk_update",
          steps_completed: valid_steps
        ))

        user.collection.update_one({ "_id" => user.id }, update_operations)
        
        Rails.logger.info "✅ Bulk onboarding update completed for user #{user.id}: #{valid_steps.join(', ')}"
        true
      rescue => e
        Rails.logger.error "❌ Bulk onboarding update failed for user #{user.id}: #{e.message}"
        false
      end
    end

    private

    def build_update_operations(step_name, context)
      {
        "$set" => {
          "onboarding_status.#{step_name}" => true,
          "onboarding_status.client_metadata.last_request" => build_metadata(context.merge(
            step_completed: step_name
          ))
        },
        "$addToSet" => {
          "onboarding_status.completed_steps" => step_name.to_s
        }
      }
    end

    def build_metadata(context)
      base_metadata = {
        "updated_at" => Time.current.iso8601,
        "step_completed" => context[:step_completed]
      }

      # Add optional context data
      optional_fields = {
        "user_agent" => context[:user_agent] || Current.request&.user_agent,
        "ip_address" => context[:ip_address] || Current.request&.remote_ip,
        "batch_size" => context[:batch_size],
        "request_id" => context[:request_id],
        "session_id" => context[:session_id],
        "steps_completed" => context[:steps_completed]
      }

      base_metadata.merge(optional_fields.compact)
    end

    # Helper method to ensure onboarding_status structure exists
    def ensure_onboarding_structure(user)
      return unless user&.persisted?

      if user.onboarding_status.blank?
        user.set("onboarding_status" => {
          "completed_steps" => [],
          "client_metadata" => {},
          "created_at" => Time.current.iso8601
        })
      end
    end
  end
end