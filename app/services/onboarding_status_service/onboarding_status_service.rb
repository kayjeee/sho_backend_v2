# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      Rails.logger.info "✅ OnboardingStatusService: Completing step '#{step_name}' for user #{user.auth0_id}"

      begin
        safe_metadata = {}
        safe_metadata["grades"]   = metadata["grades"] if metadata["grades"].is_a?(Array)
        safe_metadata["schoolId"] = metadata["schoolId"] if metadata["schoolId"].present?

        Rails.logger.debug "🔍 Raw step metadata: #{metadata.inspect}"
        Rails.logger.debug "🌐 Request context: #{request_context.inspect}"

        # ====== Update onboarding_status ======
        user.onboarding_status ||= {}
        user.onboarding_status = user.onboarding_status.to_h if user.onboarding_status.respond_to?(:to_h)
        user.onboarding_status[step_name.to_s] = safe_metadata
        user.onboarding_status_will_change!
        user.save!

        # ====== If step is 'create_grades', attempt grade creation ======
        if step_name.to_s == "create_grades" && safe_metadata["grades"].present? && safe_metadata["schoolId"].present?
          school = School.find(safe_metadata["schoolId"])

          safe_metadata["grades"].each do |grade_name|
            begin
              grade = Grade.find_or_create_by!(school_id: school.id, name: grade_name) do |g|
                g.description         = "Auto-created during onboarding"
                g.grade_level         = grade_name.gsub(/\D/, '') # extract "10" from "10th Grade"
                g.capacity            = 30
                g.status              = Grade::STATUSES['active']
                g.academic_year_start = Date.current.beginning_of_year
                g.academic_year_end   = Date.current.end_of_year
                g.fees                = 0.0
                g.min_age             = 5
                g.max_age             = 18
                g.curriculum_info     = { subjects: [] }
                g.schedule_info       = {}
              end

              Rails.logger.info "📚 Grade '#{grade_name}' ensured for school #{school.id}" if grade.persisted?
            rescue => e
              Rails.logger.error "⚠️ Failed to create grade '#{grade_name}' for school #{school.id}: #{e.message}"
              next # skip this grade, continue with the rest
            end
          end
        end

        { success: true, message: "Step '#{step_name}' completed", data: safe_metadata }
      rescue => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error completing step: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        { success: false, message: "Unexpected error occurred while completing step", errors: [e.message] }
      end
    end
  end
end
