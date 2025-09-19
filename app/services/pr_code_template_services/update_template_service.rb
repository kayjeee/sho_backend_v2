# app/services/pr_code_template_services/update_template_service.rb
module PrCodeTemplateServices
  class UpdateTemplateService
    def self.call(template, params)
      if template.update(params)
        OpenStruct.new(success?: true, pr_code_template: template)
      else
        OpenStruct.new(success?: false, errors: template.errors.full_messages)
      end
    end
  end
end
