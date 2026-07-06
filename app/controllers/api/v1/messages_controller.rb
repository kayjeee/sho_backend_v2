module Api
  module V1
    class MessagesController < ApplicationController
      before_action :set_conversation, only: [:index, :create, :search]
      before_action :set_message, only: [:react, :pin, :star]

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

      # POST /api/v1/conversations/:conversation_id/messages/:id/react
      def react
        emoji = params[:emoji]
        user_id = params[:user_id] || params[:userId] || @decoded_token&.sub

        if user_id.blank?
          return render json: { success: false, error: "User ID required for reaction" }, status: :bad_request
        end

        new_reactions = (@message.reactions || {}).dup
        new_reactions[emoji] ||= []

        unless new_reactions[emoji].include?(user_id)
          new_reactions[emoji] << user_id
          if @message.update(reactions: new_reactions)
            render json: { success: true, data: @message }, status: :ok
          else
            render json: { success: false, error: @message.errors.full_messages }, status: :unprocessable_entity
          end
        else
          render json: { success: true, data: @message, message: "Already reacted" }, status: :ok
        end
      end

      # POST /api/v1/conversations/:conversation_id/messages/:id/pin
      def pin
        if @message.update(pinned: !@message.pinned)
          render json: { success: true, data: @message }, status: :ok
        else
          render json: { success: false, error: @message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/conversations/:conversation_id/messages/:id/star
      def star
        user_id = params[:user_id] || params[:userId] || @decoded_token&.sub

        if user_id.blank?
          return render json: { success: false, error: "User ID required for starring" }, status: :bad_request
        end

        new_starred_by = (@message.starred_by || []).dup
        if new_starred_by.include?(user_id)
          new_starred_by.delete(user_id)
        else
          new_starred_by << user_id
        end

        if @message.update(starred_by: new_starred_by)
          render json: { success: true, data: @message }, status: :ok
        else
          render json: { success: false, error: @message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/conversations/:conversation_id/messages/search
      def search
        query = params[:q]
        messages = @conversation.messages.where("$text" => { "$search" => query })
        render json: { success: true, data: messages }, status: :ok
      end

      # GET /api/v1/messages/starred
      def starred
        user_id = params[:user_id] || params[:userId] || @decoded_token&.sub

        if user_id.blank?
          return render json: { success: false, error: "User ID required" }, status: :bad_request
        end

        messages = Message.where(starred_by: user_id)
        render json: { success: true, data: messages }, status: :ok
      end

      private

      def set_conversation
        @conversation = Conversation.find(params[:conversation_id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Conversation not found" }, status: :not_found
      end

      def set_message
        @message = Message.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Message not found" }, status: :not_found
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
