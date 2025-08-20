# app/services/user_services/add_school_service.rb
module UserServices
  class AddSchoolService
    Result = Struct.new(:success?, :user, :errors, :message, keyword_init: true)

    def initialize(user:, school_id:)
      @user = user
      @school_id = school_id.to_s.strip
    end

    def self.call(user:, school_id:)
      new(user: user, school_id: school_id).call
    end

    def call
      Rails.logger.debug "➕ Adding school #{@school_id} to user #{@user.auth0_id}"

      if @school_id.blank?
        Rails.logger.warn "⚠️ Missing schoolId in request."
        return Result.new(success?: false, errors: ["Missing schoolId parameter."], message: "Invalid parameters")
      end

      result = @user.add_school(@school_id)

      if result
        Rails.logger.info "✅ School #{@school_id} added to user #{@user.auth0_id}"
        Result.new(success?: true, user: @user, message: "School added successfully.")
      else
        Rails.logger.error "❌ Failed to add school #{@school_id} - #{@user.errors.full_messages.join(', ')}"
        Result.new(success?: false, errors: @user.errors.full_messages, message: "Failed to add school")
      end
    rescue StandardError => e
      Rails.logger.error "🔥 Unexpected error: #{e.message}"
      Result.new(success?: false, errors: [e.message], message: "Unexpected error occurred")
    end
  end
end
