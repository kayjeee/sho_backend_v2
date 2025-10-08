# app/services/pr_code_services/base_service.rb
module PrCodeServices
  class BaseService
    attr_reader :result, :errors

    def initialize
      @errors = []
      @result = nil
    end

    def success?
      @errors.empty?
    end

    private

    def add_error(message)
      @errors << message
    end

    def validate_presence(record, attributes)
      attributes.each do |attribute|
        value = record.send(attribute)
        add_error("#{attribute.to_s.humanize} can't be blank") if value.blank?
      end
    end
  end
end