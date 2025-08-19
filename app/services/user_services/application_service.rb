# app/services/application_service.rb
class ApplicationService
  Result = Struct.new(:success?, :data, :errors, :message, keyword_init: true)

  def self.call(*args, &block)
    new(*args, &block).call
  end

  private

  def success(data: nil, message: nil)
    Result.new(success?: true, data: data, message: message)
  end

  def failure(errors: nil, message: nil)
    Result.new(success?: false, errors: errors, message: message)
  end
end
