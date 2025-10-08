# lib/tasks/debug_onboarding.rake
namespace :debug do
  desc "Check if OnboardingStatusService changes are loaded"
  task onboarding: :environment do
    puts "🔍 Checking OnboardingStatusService..."

    # Show where the file is loaded from
    loc = OnboardingStatusService.method(:complete_step).source_location
    puts "📂 complete_step loaded from: #{loc.inspect}"

    # Check that our private method is present
    has_method = OnboardingStatusService.private_instance_methods(false).include?(:create_grades_from_metadata)
    puts "✅ create_grades_from_metadata present? #{has_method}"

    # Print first few lines of method to confirm content
    source_lines, line_no = OnboardingStatusService.instance_method(:create_grades_from_metadata).source
    puts "📜 First few lines of create_grades_from_metadata (starting at #{line_no}):"
    puts source_lines[0..5].join
  end
end
