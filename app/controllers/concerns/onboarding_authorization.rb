# app/controllers/concerns/onboarding_authorization.rb
module OnboardingAuthorization
  extend ActiveSupport::Concern

  # Validation rules for different step metadata
  STEP_VALIDATIONS = {
    'create_grades' => {
      'grades' => { type: Array, required: true },
      'schoolId' => { type: String, required: true, format: /\A[a-f\d]{24}\z/i }
    }
    # Add validations for other steps as needed
  }.freeze

  def validate_step_metadata(step_name, metadata)
    validation_rules = STEP_VALIDATIONS[step_name.to_s]
    
    return { valid: true, errors: [] } unless validation_rules

    errors = []
    metadata = metadata.to_h if metadata.respond_to?(:to_h)

    validation_rules.each do |field, rules|
      value = metadata[field]

      # Check required fields
      if rules[:required] && (value.nil? || value.blank?)
        errors << "#{field} is required"
        next
      end

      # Check type
      if rules[:type] && !value.is_a?(rules[:type])
        errors << "#{field} must be a #{rules[:type]}"
      end

      # Check format with regex
      if rules[:format] && value && !value.match?(rules[:format])
        errors << "#{field} has invalid format"
      end
    end

    { valid: errors.empty?, errors: errors }
  end

  # Optional: Add helper methods for specific validation logic
  def requires_skip_reason?(step_name)
    # Define which steps require skip reasons
    ['create_grades', 'upload_learners'].include?(step_name.to_s)
  end
end