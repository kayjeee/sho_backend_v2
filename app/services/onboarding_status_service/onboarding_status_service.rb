# app/services/onboarding_status_service.rb (or wherever complete_step lives)
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      Rails.logger.info "✅ OnboardingStatusService: Completing step '#{step_name}' for user #{user.auth0_id}"

      begin
        case step_name
        when "create_grades"
          # Ensure school is loaded
          school_id = metadata["schoolId"] || metadata[:schoolId]
          school = School.find(BSON::ObjectId.from_string(school_id))

          grades = metadata["grades"] || []
          grades.each do |grade_name|
            grade = Grade.new(
              name: grade_name,
              school: school # 🔑 attach the actual relation
            )

            if grade.save
              Rails.logger.info "✅ Grade '#{grade_name}' created for school '#{school.name}'"
            else
              Rails.logger.error "🔥 Error creating grade '#{grade_name}': #{grade.errors.full_messages.join(", ")}"
            end
          end

          # Mark onboarding step complete
          user.onboarding_status&.mark_step_complete!(step_name, metadata)

        else
          Rails.logger.warn "⚠️ Unknown onboarding step: #{step_name}"
        end

        { success: true }
      rescue => e
        Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}"
        { success: false, error: e.message }
      end
    end
  end
end
