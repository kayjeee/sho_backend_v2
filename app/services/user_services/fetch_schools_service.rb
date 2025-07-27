# In app/services/user_services/fetch_schools_service.rb
def fetch_associated_schools
  Rails.logger.debug "🏫 User#fetch_associated_schools: Fetching schools for user #{auth0_id}"
  
  school_ids = Array(self.school_ids).map(&:to_s)
  schools = School.where(:_id.in => school_ids.map { |id| BSON::ObjectId.from_string(id) })
  
  Rails.logger.info "✅ User#fetch_associated_schools: Found #{schools.count} school(s) for user #{auth0_id}"
  schools
end# app/services/user_services/fetch_schools_service.rb
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
      Rails.logger.debug "🏫 User#fetch_associated_schools: Fetching schools for user #{@user.auth0_id}"
      
      school_ids = Array(@user.school_ids).map(&:to_s)
      schools = School.where(:_id.in => school_ids.map { |id| BSON::ObjectId.from_string(id) })
      
      Rails.logger.info "✅ User#fetch_associated_schools: Found #{schools.count} school(s) for user #{@user.auth0_id}"
      schools
    end
  end
end