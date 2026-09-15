module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token = request.query_parameters[:token] || token_from_header
      if token.present?
        validation_response = Auth0Client.validate_token(token)
        decoded_token = validation_response&.decoded_token
        if decoded_token
          auth0_sub = nil
          if decoded_token.respond_to?(:token) && decoded_token.token.is_a?(Array) && decoded_token.token[0].is_a?(Hash)
            auth0_sub = decoded_token.token[0]['sub'] || decoded_token.token[0][:sub]
          elsif decoded_token.is_a?(Hash)
            auth0_sub = decoded_token['sub'] || decoded_token[:sub]
          end

          if auth0_sub.present?
            user = find_user(auth0_sub)
            return user if user
          end
        end
      end

      reject_unauthorized_connection
    end

    def token_from_header
      header = request.headers['Authorization']
      return nil unless header.present?
      header.split(' ').last if header.downcase.start_with?('bearer ')
    end

    def find_user(identifier)
      ident_str = identifier.to_s.strip
      if BSON::ObjectId.legal?(ident_str)
        u = User.where(_id: BSON::ObjectId.from_string(ident_str)).first
        return u if u
      end
      User.where(auth0_id: ident_str).first
    rescue => e
      User.where(auth0_id: identifier.to_s).first
    end
  end
end