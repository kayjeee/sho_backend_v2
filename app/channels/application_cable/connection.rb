module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      logger.add_tags "ActionCable", current_user.email
    end

    private

    def find_verified_user
      # Follow the same logic as Secured concern
      email = request.params[:user_email] || request.headers["X-User-Email"]

      if email.present? && (user = User.find_by(email: email))
        user
      else
        reject_unauthorized_connection
      end
    end
  end
end
