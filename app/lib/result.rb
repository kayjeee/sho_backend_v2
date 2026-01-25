# app/services/result.rb (or wherever your Result class is)
class Result
  attr_reader :value, :error, :errors, :user, :message

  def self.success(value = nil, **options)
    new(success: true, value: value, **options)
  end

  def self.failure(error)
    new(success: false, error: error)
  end

  def initialize(success:, value: nil, error: nil, **options)
    @success = success
    @value = value
    @user = value if value.is_a?(User)
    @error = error
    @errors = Array(error)
    @new_record = options[:new_record]
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def new_record?
    @new_record == true
  end
end