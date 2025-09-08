# app/services/onboarding_status_service.rb
class OnboardingStatusService
  class << self
    def complete_step(user, step_name, metadata = {}, request_context = {})
      Rails.logger.info "✅ OnboardingStatusService: Completing step '#{step_name}' for user #{user.auth0_id}"
      
      begin
        case step_name
        when "create_grades"
          school_id = metadata["schoolId"] || metadata[:schoolId]
          school    = School.find(BSON::ObjectId.from_string(school_id))
          
          grades = metadata["grades"] || []
          grades.each do |grade_name|
            grade = Grade.new(name: grade_name, school: school)
            if grade.save
              Rails.logger.info "✅ Grade '#{grade_name}' created for school '#{school.name}'"
            else
              Rails.logger.error "🔥 Error creating grade '#{grade_name}': #{grade.errors.full_messages.join(", ")}"
            end
          end
          
          # ✅ Mark step complete as a boolean
          user.set("onboarding_status.create_grades" => true)
          
          # Store metadata separately if you want
          user.push("onboarding_status.client_metadata" => {
            step_name => metadata.merge(request_context)
          })
          
        else
          Rails.logger.warn "⚠️ Unknown onboarding step: #{step_name}"
          
          # For unknown steps, still mark as complete with boolean
          user.set("onboarding_status.#{step_name}" => true)
          
          # Store metadata separately
          user.push("onboarding_status.client_metadata" => {
            step_name => metadata.merge(request_context)
          })
        end
        
        Rails.logger.info "✅ Step '#{step_name}' marked as complete for user #{user.auth0_id}"
        
        { success: true, data: { step_name => true } }
        
      rescue => e
        Rails.logger.error "❌ Failed to complete step '#{step_name}': #{e.message}"
        Rails.logger.error "❌ Error class: #{e.class}"
        Rails.logger.error "❌ Backtrace: #{e.backtrace.first(10).join("\n")}"
        { success: false, error: e.message }
      end
    end
  end
end