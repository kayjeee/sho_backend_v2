# frozen_string_literal: true
module UserServices
  class FetchSchoolsService
    # ✅ Entry point
    def self.call(user:)
      new(user: user).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      return [] unless user

      fetch_associated_schools
    end

    private

    attr_reader :user

    def fetch_associated_schools
      Rails.logger.debug "🏫 FetchSchoolsService: Fetching schools for user #{user.auth0_id}"

      school_ids = Array(user.school_ids).map(&:to_s)
      if school_ids.empty?
        Rails.logger.info "⚠️ FetchSchoolsService: No schools associated with user #{user.auth0_id}"
        return []
      end

      # Convert to BSON::ObjectId and query
      schools = School.where(:_id.in => school_ids.map { |id| BSON::ObjectId.from_string(id) })

      Rails.logger.info "✅ FetchSchoolsService: Found #{schools.count} school(s) for user #{user.auth0_id}"
      schools
    rescue => e
      Rails.logger.error "🔥 FetchSchoolsService Error: #{e.message}"
      []
    end
  end
end
