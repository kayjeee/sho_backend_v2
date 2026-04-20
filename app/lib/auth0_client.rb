# frozen_string_literal: true

require 'jwt'
require 'net/http'

class Auth0Client
  # Auth0 Client Objects 
  Error = Struct.new(:message, :status)
  Response = Struct.new(:decoded_token, :error)

  Token = Struct.new(:token) do
    def validate_permissions(permissions)
      required_permissions = Set.new permissions
      # Auth0 puts permissions in 'permissions' or 'scope'
      scopes = token[0]['scope'] || ""
      token_permissions = Set.new(scopes.split(" "))
      
      # Also check the 'permissions' array if present
      if token[0]['permissions']
        token_permissions.merge(token[0]['permissions'])
      end

      required_permissions <= token_permissions
    end
  end

  # --- Configuration ---
  
  def self.domain_url
    # Ensure this matches exactly what is in your Auth0 dashboard
    "https://dev-t0o26rre86m7t8lo.us.auth0.com/"
  end

  def self.audience
    # Since you're locked out, we check ENV first, then fallback.
    # Try searching your frontend code for 'audience' to get this string.
    ENV['AUTH0_AUDIENCE'] || "https://dev-t0o26rre86m7t8lo.us.auth0.com/api/v2/"
  end

  # --- Logic ---

  def self.decode_token(token, jwks_hash)
    # The JWT library wants the issuer usually without the trailing slash for validation
    issuer = domain_url.ends_with?('/') ? domain_url : "#{domain_url}/"

    JWT.decode(token, nil, true, {
                 algorithm: 'RS256',
                 iss: issuer,
                 verify_iss: true,
                 aud: audience,
                 verify_aud: true,
                 jwks: { keys: jwks_hash[:keys] }
               })
  end

  def self.get_jwks
    jwks_uri = URI("#{domain_url}.well-known/jwks.json")
    Net::HTTP.get_response jwks_uri
  rescue StandardError => e
    Rails.logger.error "Auth0 JWKS Fetch Error: #{e.message}"
    nil
  end

  def self.validate_token(token)
    jwks_response = get_jwks

    if jwks_response.nil? || !jwks_response.is_a?(Net::HTTPSuccess)
      error = Error.new('Unable to reach Auth0 for credential verification', :internal_server_error)
      return Response.new(nil, error)
    end

    jwks_hash = JSON.parse(jwks_response.body).deep_symbolize_keys
    decoded_token = decode_token(token, jwks_hash)

    Response.new(Token.new(decoded_token), nil)

  rescue JWT::ExpiredSignature
    render_auth_error('Token has expired')
  rescue JWT::InvalidAudError
    # This is likely your current issue!
    render_auth_error("Invalid audience. Expected: #{audience}")
  rescue JWT::InvalidIssuerError
    render_auth_error("Invalid issuer. Expected: #{domain_url}")
  rescue JWT::VerificationError => e
    render_auth_error("Signature verification failed: #{e.message}")
  rescue JWT::DecodeError => e
    render_auth_error("Token decode failed: #{e.message}")
  rescue StandardError => e
    render_auth_error("Internal Auth Error: #{e.message}")
  end

  private

  def self.render_auth_error(message)
    # This prints directly to your 'rails s' terminal for debugging
    puts "\e[31m[Auth0 Debug]\e[0m #{message}" 
    error = Error.new('Bad credentials', :unauthorized)
    Response.new(nil, error)
  end
end