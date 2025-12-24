namespace :onboarding do
  desc "Recalculate and fix all user onboarding statuses"
  task recalculate_all: :environment do
    puts "Starting recalculation for all user onboarding statuses..."

    User.all.each do |user|
      onboarding_status = user.onboarding_status

      if onboarding_status.nil?
        puts "User #{user.email} (ID: #{user.id}) has no onboarding status. Initializing."
        user.initialize_onboarding_status
        onboarding_status = user.onboarding_status
      end

      original_percentage = onboarding_status.completion_percentage
      original_steps = onboarding_status.total_steps_count
      original_current_step = onboarding_status.current_step

      # Re-trigger the initialization logic to set correct step counts and current step
      onboarding_status.send(:set_total_steps_based_on_user_roles)
      onboarding_status.send(:set_current_step_based_on_user_roles)

      # Recalculate percentage
      onboarding_status.calculate_completion_percentage

      if onboarding_status.changed?
        if onboarding_status.save(validate: false)
          puts "Fixed onboarding status for user #{user.email} (ID: #{user.id}):"
          puts "  - Percentage: #{original_percentage}% -> #{onboarding_status.completion_percentage}%"
          puts "  - Total Steps: #{original_steps} -> #{onboarding_status.total_steps_count}"
          puts "  - Current Step: '#{original_current_step}' -> '#{onboarding_status.current_step}'"
        else
          puts "Failed to fix onboarding status for user #{user.email} (ID: #{user.id}). Errors: #{onboarding_status.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "Onboarding status recalculation complete."
  end
end
