module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:index, :create, :react]
      before_action :set_message, only: [:react]

      # GET /api/v1/conversations/:conversation_id/messages
      def index
        Message.mark_as_delivered!(@conversation, @current_user)

        messages = @conversation.messages.order(created_at: :asc)
        serialized_messages = messages.map { |m| serialize_message(m) }
        render json: { success: true, data: serialized_messages }, status: :ok
      end

      # POST /api/v1/conversations/:conversation_id/messages
      def create
        sender = find_sender
        return unless sender

        message = @conversation.messages.build(message_params)

        # Assign the sender to the message and ensure ID consistency
        if sender.is_a?(User)
          message.sender = sender
          message.sender_id = sender.id.to_s
          message.user_id = sender.id.to_s
        end

        message.school = sender if sender.is_a?(School)

        if message.save
          render json: {
            success: true,
            data: MessageSerializer.new(message).as_json,
            message: "Message created successfully."
          }, status: :created
        else
          render json: { success: false, errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/conversations/:conversation_id/messages/:message_id/react
      def react
        emoji = params[:emoji] || params.dig(:reaction, :emoji)
        return render json: { success: false, error: "emoji is required" }, status: :bad_request if emoji.blank?

        @message.toggle_reaction!(emoji, @current_user.id)

        render json: {
          success: true,
          data: MessageSerializer.new(@message).as_json,
          message: "Reaction updated successfully."
        }, status: :ok
      end

      private

      def set_conversation
        # Scoped to @current_user for security
        @conversation = Conversation.find_by(id: params[:conversation_id], user_id: @current_user.id)
        render json: { success: false, error: "Conversation not found" }, status: :not_found unless @conversation
      end

      def set_message
        @message = @conversation.messages.find(params[:message_id] || params[:id])
        conversation = @conversation
        current_user_id = @current_user.id.to_s

        allowed = conversation.user_id.to_s == current_user_id ||
                  Array(conversation.participant_ids).map(&:to_s).include?(current_user_id)

        return if allowed

        render json: { success: false, error: "Message not found or access denied" }, status: :not_found
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Message not found" }, status: :not_found
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
        params.require(:message).permit(
          :content, :user_id, :school_id, :name, :schoolName,
          :attachment_url, :attachment_type, :attachment_name, :attachment_size
        )
      end

      def serialize_message(message)
        {
          id:        message.id.to_s,
          content:   message.content,
          sender_id: message.user_id&.to_s || message.school_id&.to_s,
          timestamp: message.created_at,
          read:      message.read,
          status:    message.status,
          reactions: message.reactions || [],
          name:      message.name,
          schoolName: message.schoolName
        }
      end

      def broadcast_messages(message_ids)
        Message.in(id: message_ids).each(&:broadcast_update!)
      end
    end
  end
end
