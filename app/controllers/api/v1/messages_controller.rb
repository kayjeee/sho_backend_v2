module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize

      # IMPORTANT:
      # Include :search so conversation access is always scoped
      # to the authenticated user.
      before_action :set_conversation,
                    only: %i[index create react search]

      before_action :set_message,
                    only: [:react]

      # =========================================================
      # GET /api/v1/conversations/:conversation_id/messages
      # =========================================================
      def index
        Message.mark_as_delivered!(@conversation, @current_user)

        messages = @conversation.messages.order(created_at: :asc)

        serialized_messages = messages.map do |message|
          serialize_message(message)
        end

        render json: {
          success: true,
          data: serialized_messages
        }, status: :ok
      end

      # =========================================================
      # GET /api/v1/conversations/:conversation_id/messages/search?q=hello
      # =========================================================
      def search
        q = params[:q].to_s.strip

        return render json: {
          success: true,
          data: []
        }, status: :ok if q.blank?

        begin
          messages =
            if q.length >= 3
              # MongoDB full-text indexed search
              @conversation.messages
                           .where("$text" => { "$search" => q })
                           .order(created_at: :desc)
                           .limit(50)
            else
              # Regex fallback for short terms
              @conversation.messages
                           .where(content: /#{Regexp.escape(q)}/i)
                           .order(created_at: :desc)
                           .limit(50)
            end

          render json: {
            success: true,
            data: messages.map { |m| serialize_message(m) }
          }, status: :ok
        rescue Mongo::Error::OperationFailure => e
          # Fallback to regex search if text index is missing or not yet built
          Rails.logger.warn "Search fallback to regex due to: #{e.message}"

          messages = @conversation.messages
                                  .where(content: /#{Regexp.escape(q)}/i)
                                  .order(created_at: :desc)
                                  .limit(50)

          render json: {
            success: true,
            data: messages.map { |m| serialize_message(m) }
          }, status: :ok
        end
      end

      # =========================================================
      # POST /api/v1/conversations/:conversation_id/messages
      # =========================================================
      def create
        sender = find_sender
        return unless sender

        # Build through association so conversation_id is linked
        message = @conversation.messages.build(message_params)

        # Ensure sender consistency
        if sender.is_a?(User)
          message.sender = sender
          message.sender_id = sender.id.to_s
          message.user_id = sender.id.to_s
        end

        # If sender is a school
        message.school = sender if sender.is_a?(School)

        if message.save
          @conversation.touch_last_message_at!

          render json: {
            success: true,
            data: serialize_message(message),
            message: "Message created successfully."
          }, status: :created
        else
          render json: {
            success: false,
            errors: message.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # =========================================================
      # POST /api/v1/conversations/:conversation_id/messages/:message_id/react
      # =========================================================
      def react
        emoji = params[:emoji] || params.dig(:reaction, :emoji)

        if emoji.blank?
          return render json: {
            success: false,
            error: "emoji is required"
          }, status: :bad_request
        end

        @message.toggle_reaction!(emoji, @current_user.id)

        render json: {
          success: true,
          data: MessageSerializer.new(@message).as_json,
          message: "Reaction updated successfully."
        }, status: :ok
      end

      private

      # =========================================================
      # CONVERSATION
      # =========================================================
      def set_conversation
        @conversation = Conversation.any_of(
          { user_id: @current_user.id },
          { participant_ids: @current_user.id.to_s }
        ).find_by(id: params[:conversation_id])

        return if @conversation.present?

        render json: {
          success: false,
          error: "Conversation not found"
        }, status: :not_found
      end

      # =========================================================
      # MESSAGE
      # =========================================================
      def set_message
        @message = @conversation.messages.find(
          params[:message_id] || params[:id]
        )

        conversation = @conversation
        current_user_id = @current_user.id.to_s

        allowed =
          conversation.user_id.to_s == current_user_id ||
          Array(conversation.participant_ids)
            .map(&:to_s)
            .include?(current_user_id)

        return if allowed

        render json: {
          success: false,
          error: "Message not found or access denied"
        }, status: :not_found
      rescue Mongoid::Errors::DocumentNotFound
        render json: {
          success: false,
          error: "Message not found"
        }, status: :not_found
      end

      # =========================================================
      # SENDER
      # =========================================================
      def find_sender
        # A user may only send as themselves
        school_id = params.dig(:message, :school_id)

        # Optional school context
        if school_id.present?
          return @current_user
        end

        return @current_user if @current_user.present?

        render json: {
          success: false,
          error: "Sender information is missing"
        }, status: :bad_request

        nil
      end

      # =========================================================
      # PARAMS
      # =========================================================
      def message_params
        params.require(:message).permit(
          :content,
          :user_id,
          :school_id,
          :name,
          :schoolName,
          :attachment_url,
          :attachment_type,
          :attachment_name,
          :attachment_size
        )
      end

      # =========================================================
      # SERIALIZATION
      # =========================================================
      def serialize_message(message)
        MessageSerializer.new(message).as_json
      end

      # =========================================================
      # BROADCAST HELPERS
      # =========================================================
      def broadcast_messages(message_ids)
        Message.in(id: message_ids).each(&:broadcast_update!)
      end
    end
  end
end