# app/services/pr_code_services/validate_pr_code_service.rb
module PrCodeServices
  class ValidatePrCodeService < BaseService
    def initialize(pr_code, school_id, purpose = nil)
      super()
      @pr_code = pr_code
      @school_id = school_id
      @purpose = purpose
    end

    def call
      validate_pr_code
      return unless success?

      validate_school
      return unless success?

      validate_purpose
      return unless success?

      validate_expiration
      return unless success?

      validate_status
      @result = @pr_code_record
    end

    private

    def validate_pr_code
      @pr_code_record = PrCode.find_by(code: @pr_code)
      add_error('PR code not found') if @pr_code_record.blank?
    end

    def validate_school
      return if @pr_code_record.blank?
      
      if @pr_code_record.school_id != @school_id.to_i
        add_error('PR code does not belong to this school')
      end
    end

    def validate_purpose
      return if @pr_code_record.blank? || @purpose.blank?
      
      if @pr_code_record.purpose != @purpose
        add_error("PR code is not valid for #{@purpose} purpose")
      end
    end

    def validate_expiration
      return if @pr_code_record.blank?
      
      if @pr_code_record.expired?
        @pr_code_record.update!(status: 'expired')
        add_error('PR code has expired')
      end
    end

    def validate_status
      return if @pr_code_record.blank?
      
      unless @pr_code_record.active?
        add_error("PR code is #{@pr_code_record.status}")
      end
    end
  end
end