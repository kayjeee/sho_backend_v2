# app/services/pr_code_template_services/destroy_template_service.rb
module PrCodeTemplateServices
  class DestroyTemplateService
    def self.call(template)
      # Add any business logic before destroying, e.g., checking dependencies
      if template.destroy
        OpenStruct.new(success?: true)
      else
        OpenStruct.new(success?: false, errors: ['Could not delete template'])
      end
    end
  end
end
