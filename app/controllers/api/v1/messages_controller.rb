module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authenticate_user!
      before_action :set_conversation, only: [:index, :create]

      # GET /api/v1/conversations/:conversation_id/messages
      def index
        unless @conversation.participant?(@current_user)
          return render json: { success: false, error: "Forbidden: Not a participant in this conversation" }, status: :forbidden
        end

        messages = @conversation.messages.order(created_at: :asc).to_a

        # Batch lookup users for efficiency (no N+1)
        user_ids = messages.map(&:user_id).compact.map(&:to_s).uniq
        user_bsons = user_ids.map { |id| BSON::ObjectId.legal?(id) ? BSON::ObjectId.from_string(id) : nil }.compact
        all_lookup_ids = (user_ids + user_bsons).uniq

        users_map = if all_lookup_ids.any?
                      User.where(:id.in => all_lookup_ids).each_with_object({}) do |user, hash|
                        hash[user.id.to_s] = {
                          email: user.email,
                          name: user.full_name.presence || user.name.presence
                        }.compact
                      end
                    else
                      {}
                    end

        serialized_messages = messages.map do |msg|
          u_id_str = msg.user_id&.to_s
          sender_info = u_id_str.present? ? users_map[u_id_str] : nil

          {
            id: msg.id.to_s,
            content: msg.content,
            created_at: msg.created_at&.iso8601,
            user_id: u_id_str,
            sender: sender_info
          }
        end

        render json: { success: true, data: serialized_messages }, status: :ok
      end

      # POST /api/v1/conversations/:conversation_id/messages
      def create
        unless @conversation.participant?(@current_user)
          return render json: { success: false, error: "Forbidden: Sender is not a participant in this conversation" }, status: :forbidden
        end

        message = @conversation.messages.build(message_params)
        message.user = @current_user

        if message.save
          @conversation.touch if @conversation.respond_to?(:touch)
          render json: { success: true, data: message, message: "Message created successfully." }, status: :created
        else
          render json: { success: false, errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def authenticate_user!
        authorize
        return if performed?

        auth0_sub = nil
        if @decoded_token && @decoded_token.respond_to?(:token) && @decoded_token.token.is_a?(Array) && @decoded_token.token[0].is_a?(Hash)
          auth0_sub = @decoded_token.token[0]['sub'] || @decoded_token.token[0][:sub]
        elsif @decoded_token.is_a?(Hash)
          auth0_sub = @decoded_token['sub'] || @decoded_token[:sub]
        end

        if auth0_sub.blank?
          render json: { success: false, error: "Unauthorized: Missing token subject" }, status: :unauthorized
          return
        end

        @current_user = find_user(auth0_sub)
        if @current_user.nil?
          render json: { success: false, error: "Unauthorized: User not found for token subject" }, status: :unauthorized
          return
        end
      end

      def set_conversation
        @conversation = Conversation.find_by(id: params[:conversation_id])
        render json: { success: false, error: "Conversation not found" }, status: :not_found unless @conversation
      end

      def find_user(identifier)
        return nil if identifier.blank?

        ident_str = identifier.to_s.strip

        if BSON::ObjectId.legal?(ident_str)
          u = User.where(_id: BSON::ObjectId.from_string(ident_str)).first
          return u if u
        end

        User.where(auth0_id: ident_str).first
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
        User.where(auth0_id: identifier.to_s).first
      end

      def message_params
        raw_msg = params[:message] || params
        raw_msg.permit(:content, :name, :schoolName)
      end
    end
  end
end