module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :set_conversation, only: [:show, :destroy]

      # GET /api/v1/conversations
      def index
        if params[:school_id].present?
          conversations = Conversation.where(school_id: params[:school_id]).order(last_message_at: :desc)
        elsif params[:user_id].present?
          conversations = Conversation.where(user_id: params[:user_id]).order(last_message_at: :desc)
        else
          return render json: { success: false, error: "Missing school_id or user_id" }, status: :bad_request
        end

        render json: { success: true, data: conversations }, status: :ok
      end

      # GET /api/v1/conversations/:id
      def show
        render json: { success: true, data: @conversation }, status: :ok
      end

      # POST /api/v1/conversations
      def create
        conversation_params = params[:conversation] || {}
        school_id = conversation_params[:school_id].presence || params[:school_id]
        user_identifier = conversation_params[:user_id].presence || params[:user_id]

        Rails.logger.info(
          "POST /api/v1/conversations received school_id=#{school_id.inspect} " \
          "user_id=#{user_identifier.inspect} request_id=#{request.request_id}"
        )

        if school_id.blank? || user_identifier.blank?
          return render json: { success: false, error: "Missing parameters: school_id and user_id are required" }, status: :bad_request
        end

        user = find_user(user_identifier)
        return render json: { success: false, error: "User not found" }, status: :not_found unless user

        conversation = Conversation.find_or_create_by_school_and_user(school_id, user.id)

        if conversation.persisted?
          render json: { success: true, data: conversation, message: "Conversation created or retrieved" }, status: :ok
        else
          render json: { success: false, errors: conversation.errors.full_messages }, status: :unprocessable_entity
        end
      end
    
    
      # DELETE /api/v1/conversations/:id
      def destroy
        if @conversation.destroy
          render json: { success: true, message: "Conversation deleted successfully" }, status: :ok
        else
          render json: { success: false, error: "Failed to delete conversation" }, status: :unprocessable_entity
        end
      end 

      private

      def set_conversation
        @conversation = Conversation.find_by(id: params[:id], school_id: params[:school_id], user_id: params[:user_id])
        return render json: { success: false, error: "Conversation not found" }, status: :not_found unless @conversation
      end

      def find_user(identifier)
        user = User.find_by(id: identifier) if object_id?(identifier)
        user || User.find_by(auth0_id: identifier)
      rescue Mongoid::Errors::InvalidFind
        User.find_by(auth0_id: identifier)
      end

      def object_id?(value)
        value.to_s.match?(/\A[0-9a-f]{24}\z/i)
      end
    end
  end
end
