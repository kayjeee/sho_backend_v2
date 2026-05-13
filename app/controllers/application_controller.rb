# app/controllers/api/v1/application_controller.rb
class ApplicationController < ActionController::API
  include Secured
  # We'll let specific controllers define which actions need authorization
  # to avoid breaking public endpoints.
  before_action :update_last_seen_at

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

  protected

  def render_success(message: nil, data: {}, status: :ok)
    render json: { success: true, status: 'success', message: message, data: data }, status: status
  end

  def render_error(message, errors = [], status: :unprocessable_entity)
    render json: { success: false, status: 'error', message: message, errors: Array(errors) }, status: status
  end

  def handle_exception(error, fallback_message)
    Rails.logger.error("❌ #{fallback_message}: #{error.message}")
    render json: { success: false, status: 'error', message: fallback_message, errors: [error.message] }, status: :internal_server_error
  end

  def update_last_seen_at
    current_user&.touch_last_seen!
  end
end
