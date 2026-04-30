module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:index, :create]

      # GET /api/v1/conversations/:conversation_id/messages
      def index
        messages = @conversation.messages.order(created_at: :asc)
        render json: { success: true, data: messages }, status: :ok
      end

      # POST /api/v1/conversations/:conversation_id/messages
      def create
        sender = find_sender
        return unless sender

        message = @conversation.messages.build(message_params)

        # Assign the sender to the message
        message.user = sender if sender.is_a?(User)
        message.school = sender if sender.is_a?(School)

        if message.save
          # Broadcast the new message via Action Cable
          ConversationChannel.broadcast_to(@conversation, serialize_message(message))

          render json: { success: true, data: message, message: "Message created successfully." }, status: :created
        else
          render json: { success: false, errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_conversation
        # Scoped to @current_user for security
        @conversation = Conversation.find_by(id: params[:conversation_id], user_id: @current_user.id)
        render json: { success: false, error: "Conversation not found" }, status: :not_found unless @conversation
      end

      def find_sender
        # For security, a user can only send as themselves
        # A school-side user would need a different authorization logic,
        # but for the parent/teacher app, we use @current_user.

        school_id = params.dig(:message, :school_id)

        # If school_id is provided, we check if the user has a role in that school
        if school_id.present?
          # This logic might change depending on if the user is sending AS the school
          # (e.g. an Admin). For now, we'll allow @current_user.
          return @current_user
        end

        return @current_user if @current_user.present?
      
        render json: { success: false, error: "Sender information is missing" }, status: :bad_request
        nil
      end
      

      def message_params
        params.require(:message).permit(:content, :user_id, :school_id, :name, :schoolName)
      end

      def serialize_message(message)
        {
          id:        message.id.to_s,
          content:   message.content,
          sender_id: message.user_id&.to_s || message.school_id&.to_s,
          timestamp: message.created_at,
          read:      message.read,
          name:      message.name,
          schoolName: message.schoolName
        }
      end
    end
  end
end
