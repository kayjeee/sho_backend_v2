# app/services/pr_code_template_services/create_template_service.rb
module PrCodeTemplateServices
  class CreateTemplateService
    def self.call(params, user)
      template = PrCodeTemplate.new(params)
      # If you have a multi-tenant setup, you would associate the template
      # with the current user's school. For example:
      # template.school = user.school if user.present?
      
      if template.save
        OpenStruct.new(success?: true, pr_code_template: template)
      else
        OpenStruct.new(success?: false, errors: template.errors.full_messages)
      end
    end
  end
end
