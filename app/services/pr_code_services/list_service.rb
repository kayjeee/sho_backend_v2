# app/services/pr_code_services/list_service.rb
module PrCodeServices
  class ListService
    def self.call(school)
      # In a real app, you might have pagination
      school.pr_codes
    end
  end
end
