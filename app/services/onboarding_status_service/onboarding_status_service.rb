# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      Rails.logger.info "✅ OnboardingStatusService: Completing step herer bbybby'#{step_name}' for user #{user.auth0_id}"

      begin
        # -----------------------------------
        # 1. Extract only safe fields for persistence
        # -----------------------------------
        safe_metadata = {}
        safe_metadata["grades"]   = Array.wrap(metadata["grades"]).compact if metadata["grades"].present?
        safe_metadata["schoolId"] = metadata["schoolId"] if metadata["schoolId"].present?

        # -----------------------------------
        # 2. Log the full metadata + request context (not persisted)
        # -----------------------------------
        Rails.logger.debug "🔍 Raw step metadata: #{metadata.inspect}"
        Rails.logger.debug "🌐 Request context: #{request_context.inspect}"

        # -----------------------------------
        # 3. Persist onboarding_status
        # -----------------------------------
        user.onboarding_status ||= {}
        user.onboarding_status = user.onboarding_status.to_h if user.onboarding_status.respond_to?(:to_h)
        user.onboarding_status[step_name.to_s] = safe_metadata

        user.onboarding_status_will_change!
        user.save!

        Rails.logger.info "🎉 Step '#{step_name}' completed for user #{user.auth0_id} with data: #{safe_metadata.inspect}"

        # -----------------------------------
        # 4. Handle side-effects for specific steps
        # -----------------------------------
        create_grades_from_metadata(user, safe_metadata) if step_name.to_s == "create_grades"

        { success: true, message: "Step '#{step_name}' completed", data: safe_metadata }
      rescue => e
        Rails.logger.error "🔥 OnboardingStatusService: Unexpected error completing step: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        { success: false, message: "Unexpected error occurred while completing step", errors: [e.message] }
      end
    end

    private

    def create_grades_from_metadata(user, metadata)
      grades    = Array.wrap(metadata["grades"]).compact
      school_id = metadata["schoolId"]

      Rails.logger.debug "🎯 create_grades_from_metadata called with grades=#{grades.inspect}, school_id=#{school_id.inspect}"

      return unless grades.any? && school_id.present?

      # Academic year (current calendar year)
      current_year        = Date.current.year
      academic_year_start = Date.new(current_year, 1, 1)
      academic_year_end   = Date.new(current_year, 12, 31)

      grades.each do |grade_name|
        begin
          grade = Grade.where(name: grade_name, school_id: school_id).first_or_create!(
            grade_level: grade_name.to_s,
            description: "Auto-created during onboarding",
            capacity: 30,
            status: 0, # 'active'
            min_age: 5,
            max_age: 18,
            fees: 0.0,
            academic_year_start: academic_year_start,
            academic_year_end: academic_year_end,
            curriculum_info: {},
            schedule_info: {}
          )

          if grade.persisted?
            Rails.logger.info "✅ Grade '#{grade_name}' is now present for school #{school_id} (id: #{grade.id})"
          else
            Rails.logger.warn "⚠️ Grade '#{grade_name}' did not persist for school #{school_id}"
          end
        rescue Mongoid::Errors::Validations => e
          Rails.logger.warn "⚠️ Validation failed for grade '#{grade_name}' in school #{school_id}: #{e.message}"
        rescue => e
          Rails.logger.error "🔥 Unexpected error while creating grade '#{grade_name}' for school #{school_id}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      # -----------------------------------
      # 5. Log all grades for that school
      # -----------------------------------
      all_grades = Grade.where(school_id: school_id).to_a
      Rails.logger.info "📊 All grades for school #{school_id}:"
      all_grades.each do |g|
        Rails.logger.info "   - #{g.name} (level: #{g.grade_level}, status: #{g.status})"
      end
    end
  end
end
