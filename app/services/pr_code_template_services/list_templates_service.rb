# app/services/pr_code_template_services/list_templates_service.rb
module PrCodeTemplateServices
  class ListTemplatesService
    def self.call(user)
      # For a multi-tenant application, this service should filter templates
      # to only those belonging to the user's school, plus any default templates.
      # if user.present?
      #   PrCodeTemplate.where(school: user.school).or(PrCodeTemplate.where(is_default: true))
      # else
      #   PrCodeTemplate.where(is_default: true)
      # end
      PrCodeTemplate.all
    end
  end
end
