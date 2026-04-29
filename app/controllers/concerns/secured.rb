# frozen_string_literal: true

module Secured
  extend ActiveSupport::Concern

  def authorize
    # Identification: The system has moved away from JWT/Auth0 tokens for local development.
    # Users are now identified by a custom header X-User-Email or a user_email parameter.
    email = request.headers['X-User-Email'] || params[:user_email]

    if email.blank?
      render json: {
        success: false,
        error: 'Missing identification: X-User-Email header or user_email parameter required'
      }, status: :unauthorized
      return
    end

    @current_user ||= User.find_by(email: email)

    if @current_user.nil?
      render json: {
        success: false,
        error: "Unauthorized: User with email '#{email}' not found"
      }, status: :unauthorized
      return
    end

    Rails.logger.info "DEBUG: Authorized as #{@current_user.email} (ID: #{@current_user.id})"
  end
end
