# app/services/user_services/add_school_service.rb
module UserServices
  class AddSchoolService < ApplicationService
    def initialize(user:, school_id:)
      @user = user
      @school_id = school_id.to_s.strip
    end

    def call
      Rails.logger.debug "➕ UserServices::AddSchoolService: Adding school #{@school_id} to user #{@user.auth0_id}"
      
      if @school_id.blank?
        Rails.logger.warn "⚠️ UserServices::AddSchoolService: Missing schoolId in request."
        return failure(error: "Missing schoolId parameter.")
      end
      
      result = @user.add_school(@school_id)
      
      if result
        Rails.logger.info "✅ UserServices::AddSchoolService: School #{@school_id} added to user #{@user.auth0_id}"
        success(user: @user, message: "School added successfully.")
      else
        Rails.logger.error "❌ UserServices::AddSchoolService: Failed to add school #{@school_id} - #{@user.errors.full_messages.join(', ')}"
        failure(errors: @user.errors.full_messages)
      end
    end
  end
end