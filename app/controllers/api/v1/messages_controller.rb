module Api
  module V1
    class MessagesController < ApplicationController
      before_action :set_conversation, only: [:index, :create]

      # GET /api/v1/conversations/:conversation_id/messages
      def index
        requesting_user_id = params[:requesting_user_id] || params[:user_id] || params[:userId]
        if requesting_user_id.present? && !@conversation.participant?(requesting_user_id)
          return render json: { success: false, error: "Forbidden: Not a participant in this conversation" }, status: :forbidden
        end

        messages = @conversation.messages.order(created_at: :asc)
        render json: { success: true, data: messages }, status: :ok
      end

      # POST /api/v1/conversations/:conversation_id/messages
      def create
        sender = find_sender
        return unless sender

        # Authorization check for group conversations
        sender_user_id = sender.is_a?(User) ? sender.id.to_s : (sender.respond_to?(:auth0_id) ? sender.id.to_s : nil)
        if sender_user_id.present? && !@conversation.participant?(sender_user_id)
          return render json: { success: false, error: "Forbidden: Sender is not a participant in this conversation" }, status: :forbidden
        end

        message = @conversation.messages.build(message_params)

        # Assign the sender to the message
        message.user = sender if sender.is_a?(User)
        message.school = sender if sender.is_a?(School)

        if message.save
          # Touch conversation to update timestamps
          @conversation.touch if @conversation.respond_to?(:touch)

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
        user_id = params.dig(:message, :user_id) || params[:user_id]
        school_id = params.dig(:message, :school_id) || params[:school_id]

        sender = User.find_by(id: user_id) if user_id.present? && object_id?(user_id)
        sender ||= User.find_by(auth0_id: user_id) if user_id.present?
        sender ||= School.find_by(id: school_id) if school_id.present?

        return sender if sender.present?

        render json: { success: false, error: "Sender information is missing" }, status: :bad_request
        nil
      end

      def object_id?(value)
        value.to_s.match?(/\A[0-9a-f]{24}\z/i)
      end

      def message_params
        params.require(:message).permit(:content, :user_id, :school_id, :name, :schoolName)
      end
    end
  end
end
