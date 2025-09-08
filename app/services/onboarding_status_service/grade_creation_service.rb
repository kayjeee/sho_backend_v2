# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      Rails.logger.info "✅ OnboardingStatusService: Completing step '#{step_name}' for user #{user.auth0_id}"

      begin
        case step_name
        when "create_grades"
          school_id = metadata["schoolId"] || metadata[:schoolId]
          school = School.find(BSON::ObjectId.from_string(school_id))

          grades = metadata["grades"] || []
          grades.each do |grade_name|
            grade = Grade.new(
              name: grade_name,
              school: school # attach relation, not just id
            )

            if grade.save
              Rails.logger.info "✅ Grade '#{grade_name}' created for school '#{school.name}'"
            else
              Rails.logger.error "🔥 Error creating grade '#{grade_name}': #{grade.errors.full_messages.join(", ")}"
            end
          end
        else
          Rails.logger.warn "⚠️ Unknown onboarding step: #{step_name}"
        end

        # 🔍 DEBUG: Log current state before updating
        Rails.logger.info "🔍 BEFORE UPDATE - User #{user.id}:"
        Rails.logger.info "   - onboarding_status: #{user.onboarding_status.inspect}"
        Rails.logger.info "   - onboarding_status.nil?: #{user.onboarding_status.nil?}"
        
        if user.onboarding_status
          Rails.logger.info "   - create_grades current value: #{user.onboarding_status['create_grades'] || user.onboarding_status.create_grades rescue 'ERROR_ACCESSING'}"
        end

        # ✅ Handle onboarding_status creation/update logic
        if user.onboarding_status.nil?
          Rails.logger.info "🔧 STEP 1: onboarding_status is nil, creating new object..."
          
          # Create onboarding_status with the step already set to true
          update_result = user.set(onboarding_status: { step_name => true })
          Rails.logger.info "🔧 Initial set result: #{update_result}"
          
          user.reload
          Rails.logger.info "🔧 AFTER RELOAD - onboarding_status: #{user.onboarding_status.inspect}"
          
        else
          Rails.logger.info "🔧 STEP 2: onboarding_status exists, updating #{step_name} field..."
          Rails.logger.info "   - Current #{step_name} value: #{user.onboarding_status[step_name] rescue 'ERROR_ACCESSING'}"
          
          # Update the specific step field
          update_query = "onboarding_status.#{step_name}"
          Rails.logger.info "🔧 Setting #{update_query} = true"
          
          update_result = user.set(update_query => true)
          Rails.logger.info "🔧 Update result: #{update_result}"
          
          user.reload
          Rails.logger.info "🔧 AFTER UPDATE & RELOAD:"
          Rails.logger.info "   - onboarding_status: #{user.onboarding_status.inspect}"
          Rails.logger.info "   - #{step_name} value: #{user.onboarding_status[step_name] rescue 'ERROR_ACCESSING'}"
        end

        # 🔍 DEBUG: Verify the update worked
        Rails.logger.info "🔍 FINAL VERIFICATION:"
        final_user = User.find(user.id)
        Rails.logger.info "   - Fresh user from DB - onboarding_status: #{final_user.onboarding_status.inspect}"
        if final_user.onboarding_status
          final_value = final_user.onboarding_status[step_name] || final_user.onboarding_status.send(step_name.to_sym) rescue nil
          Rails.logger.info "   - Final #{step_name} value: #{final_value}"
          
          if final_value == true
            Rails.logger.info "✅ SUCCESS: #{step_name} was successfully set to true"
          else
            Rails.logger.error "❌ FAILURE: #{step_name} is still not true! Value: #{final_value}"
          end
        else
          Rails.logger.error "❌ CRITICAL: onboarding_status is still nil after update attempt!"
        end

        # Also update progress counters and metadata if the onboarding_status object has that method
        if user.onboarding_status.respond_to?(:mark_step_complete!)
          Rails.logger.info "🔧 Calling mark_step_complete! method..."
          user.onboarding_status.mark_step_complete!(step_name, metadata)
        else
          Rails.logger.info "ℹ️ onboarding_status doesn't have mark_step_complete! method"
        end
        
        save_result = user.save!
        Rails.logger.info "💾 Final save result: #{save_result}"

        { success: true }
      rescue => e
        Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}"
        Rails.logger.error "❌ Error class: #{e.class}"
        Rails.logger.error "❌ Backtrace: #{e.backtrace.first(10).join("\n")}"
        Rails.logger.error "❌ User state at error - onboarding_status: #{user.onboarding_status.inspect rescue 'ERROR_INSPECTING'}"
        { success: false, error: e.message }
      end
    end
  end
end