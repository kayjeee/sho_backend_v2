# app/services/pr_code_services/generate_pr_code_service.rb
module PrCodeServices
  class GeneratePrCodeService < BaseService
    def initialize(school, purpose, user = nil, metadata = {})
      super()
      @school = school
      @purpose = purpose
      @user = user
      @metadata = metadata
    end

    def call
      validate_inputs
      return unless success?

      generate_unique_code
      return unless success?

      create_pr_code
    end

    private

    def validate_inputs
      add_error('School is required') if @school.blank?
      add_error('Purpose is required') if @purpose.blank?
      add_error('Invalid purpose') unless valid_purpose?
    end

    def valid_purpose?
      %w[enrollment payment registration verification].include?(@purpose)
    end

    def generate_unique_code
      max_attempts = 10
      attempts = 0

      while attempts < max_attempts
        @code = generate_code
        break unless PrCode.exists?(code: @code, school_id: @school.id)
        attempts += 1
      end

      if attempts >= max_attempts
        add_error('Failed to generate unique PR code')
      end
    end

    def generate_code
      # Generate a PR code - you can customize this format
      # Example: SCH-ABC123-XYZ789
      prefix = @school.code.presence || 'SCH'
      random_part = SecureRandom.alphanumeric(9).upcase.scan(/.{3}/).join('-')
      "#{prefix}-#{random_part}"
    end

    def create_pr_code
      expires_at = determine_expiration

      @pr_code = PrCode.new(
        code: @code,
        school: @school,
        user: @user,
        purpose: @purpose,
        metadata: @metadata,
        expires_at: expires_at,
        status: 'active'
      )

      if @pr_code.save
        @result = @pr_code
      else
        add_error(@pr_code.errors.full_messages.join(', '))
      end
    end

    def determine_expiration
      case @purpose
      when 'payment'
        30.minutes.from_now # Short expiration for payments
      when 'enrollment'
        7.days.from_now # Longer for enrollments
      else
        24.hours.from_now # Default
      end
    end
  end
end