module Api
  module V1
    class MessagesController < ApplicationController
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
          render json: { success: true, data: message, message: "Message created successfully." }, status: :created
        else
          render json: { success: false, errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_conversation
        @conversation = Conversation.find_by(id: params[:conversation_id])
        render json: { success: false, error: "Conversation not found" }, status: :not_found unless @conversation
      end

      def find_sender
        user_id = params.dig(:message, :user_id)
        school_id = params.dig(:message, :school_id)
      
        sender = User.find_by(id: user_id) if user_id.present?
        sender ||= School.find_by(id: school_id) if school_id.present?
      
        return sender if sender.present?
      
        render json: { success: false, error: "Sender information is missing" }, status: :bad_request
        nil
      end
      

      def message_params
        params.require(:message).permit(:content, :user_id, :school_id, :name, :schoolName)
      end
    end
  end
end
