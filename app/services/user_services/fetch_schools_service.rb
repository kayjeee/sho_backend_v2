# app/services/user_services/fetch_schools_service.rb
module UserServices
  class FetchSchoolsService
    def initialize(user:)
      @user = user
    end

    def call
      fetch_associated_schools
    end

    private

    attr_reader :user

    def fetch_associated_schools
      Rails.logger.debug "🏫 User#fetch_associated_schools: Fetching schools for user #{user.auth0_id}"

      # Collect from user's embedded school_ids array
      direct_ids = Array(user.school_ids).map(&:to_s)

      # Collect from UserSchoolRole join table
      role_ids = UserSchoolRole.where(user_id: user.id).pluck(:school_id).map(&:to_s)

      # Merge and deduplicate
      all_ids = (direct_ids + role_ids).uniq

      schools = if all_ids.any?
                  School.where(:_id.in => all_ids.map { |id| BSON::ObjectId.from_string(id) })
                else
                  []
                end

      Rails.logger.info "✅ User#fetch_associated_schools: Found #{schools.count} school(s) for user #{user.auth0_id}"
      schools
    end
  end
end
