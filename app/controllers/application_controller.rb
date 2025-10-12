# app/controllers/api/v1/application_controller.rb
class ApplicationController < ActionController::API
  include Secured

  # Health check endpoint
  def health
    render json: {
      status: 'healthy',
      env: Rails.env,
      time: Time.current.iso8601
    }, status: :ok
  end

  # API root endpoint
  def index
    render json: {
      message: 'Welcome to the SchoolHeadOffice API v1 🚀',
      version: 'v1',
      docs: '/api/docs',
      timestamp: Time.current.iso8601
    }, status: :ok
  end

  # Rescue from standard errors to avoid 500 crashes in production
  rescue_from StandardError do |exception|
    Rails.logger.error("🔥 API Error: #{exception.message}\n#{exception.backtrace.take(5).join("\n")}")

    render json: {
      success: false,
      error: exception.message,
      backtrace: Rails.env.development? ? exception.backtrace : nil
    }, status: :internal_server_error
  end
end
