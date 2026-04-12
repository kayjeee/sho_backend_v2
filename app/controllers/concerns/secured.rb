# frozen_string_literal: true

module Secured
    extend ActiveSupport::Concern
  
    REQUIRES_AUTHENTICATION = { message: 'Requires authentication' }.freeze
    BAD_CREDENTIALS = {
      message: 'Bad credentials'
    }.freeze
    MALFORMED_AUTHORIZATION_HEADER = {
      error: 'invalid_request',
      error_description: 'Authorization header value must follow this format: Bearer access-token',
      message: 'Bad credentials'
    }.freeze
    INSUFFICIENT_PERMISSIONS = {
      error: 'insufficient_permissions',
      error_description: 'The access token does not contain the required permissions',
      message: 'Permission denied'
    }.freeze
  
    def authorize
      token = token_from_request
  
      return if performed?
  
      validation_response = Auth0Client.validate_token(token)
  
      if validation_response.error
        render json: { message: validation_response.error.message }, status: validation_response.error.status
        return
      end

      @decoded_token = validation_response.decoded_token

      # Automatically set @current_user based on the Auth0 sub claim
      # The @decoded_token is a Auth0Client::Token struct which wraps the result of JWT.decode
      # JWT.decode returns an array [payload, header]
      payload = @decoded_token.token[0]
      sub = payload['sub']
      email = payload['email']

      puts "Incoming Token Sub: #{sub}"
      Rails.logger.debug "[AUTH] Incoming Token Sub: #{sub}, Email: #{email}"

      # Flexible lookup: auth0_id first, then fallback to email
      @current_user = User.find_by(auth0_id: sub) || User.find_by(email: email)

      if @current_user
        # Link auth0_id if it's missing or different (e.g. found by email)
        if @current_user.auth0_id != sub
          @current_user.update(auth0_id: sub)
          Rails.logger.info "Updated User #{@current_user.email} with new Auth0 ID: #{sub}"
        end
      else
        # If they truly don't exist, create them so the app can continue
        @current_user = User.create!(
          auth0_id: sub,
          email: email,
          name: payload['name'] || email,
          status: "active"
        )
        Rails.logger.info "Created new User #{@current_user.email} with Auth0 ID: #{sub}"
      end

      puts "DEBUG: Authorized as #{@current_user.email}"
    end
  
    def validate_permissions(permissions)
      raise 'validate_permissions needs to be called with a block' unless block_given?
      return yield if @decoded_token.validate_permissions(permissions)
  
      render json: INSUFFICIENT_PERMISSIONS, status: :forbidden
    end
  
    private
  
    def token_from_request
      authorization_header_elements = request.headers['Authorization']&.split
  
      render json: REQUIRES_AUTHENTICATION, status: :unauthorized and return unless authorization_header_elements
  
      unless authorization_header_elements.length == 2
        render json: MALFORMED_AUTHORIZATION_HEADER,
               status: :unauthorized and return
      end
  
      scheme, token = authorization_header_elements
  
      render json: BAD_CREDENTIALS, status: :unauthorized and return unless scheme.downcase == 'bearer'
  
      token
    end
  end