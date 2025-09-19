# app/services/pr_code_services/destroy_service.rb
module PrCodeServices
  class DestroyService
    def self.call(pr_code)
      if pr_code.destroy
        OpenStruct.new(success?: true)
      else
        OpenStruct.new(success?: false, errors: ['Could not delete PR code'])
      end
    end
  end
end
