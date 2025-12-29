namespace :onboarding do
  desc "Recalculate and fix all user onboarding statuses to correct percentages, step counts, and current steps"
  task fix_all: :environment do
    puts "Starting recalculation for all user onboarding statuses..."

    User.all.no_timeout.each do |user|
      onboarding_status = user.onboarding_status

      unless onboarding_status
        puts "User #{user.email} (ID: #{user.id}) is missing an onboarding status. Initializing."
        user.send(:ensure_onboarding_status)
        user.send(:initialize_onboarding_status)
        user.save(validate: false)
        onboarding_status = user.reload.onboarding_status
        puts "  -> Initialized with step: '#{onboarding_status.current_step}', total steps: #{onboarding_status.total_steps_count}"
        next
      end

      original_percentage = onboarding_status.completion_percentage
      original_steps = onboarding_status.total_steps_count
      original_current_step = onboarding_status.current_step

      # Re-trigger the initialization logic from the OnboardingStatus model
      onboarding_status.send(:set_total_steps_based_on_user_roles)
      onboarding_status.send(:set_current_step_based_on_user_roles)

      # Recalculate the completion percentage
      onboarding_status.calculate_completion_percentage

      if onboarding_status.changed?
        puts "Fixing onboarding status for user #{user.email} (ID: #{user.id}):"
        puts "  - Percentage: #{original_percentage}% -> #{onboarding_status.completion_percentage}%" if original_percentage != onboarding_status.completion_percentage
        puts "  - Total Steps: #{original_steps} -> #{onboarding_status.total_steps_count}" if original_steps != onboarding_status.total_steps_count
        puts "  - Current Step: '#{original_current_step}' -> '#{onboarding_status.current_step}'" if original_current_step != onboarding_status.current_step

        # Mongoid embedded documents are saved when the parent is saved
        unless user.save(validate: false)
          puts "  -> FAILED to save user #{user.email}. Errors: #{user.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "Onboarding status recalculation complete."
  end
end
