# app/services/pr_code_services/show_service.rb
module PrCodeServices
  class ShowService
    def self.call(code)
      PrCode.find_by(code: code)
    end
  end
end
