module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :set_conversation, only: [:show, :destroy, :read, :typing]

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
     # POST /api/v1/conversations
     def create
      school_id = params[:conversation][:school_id]
      user_id = params[:conversation][:user_id]
    
      if school_id.blank? || user_id.blank?
        return render json: { success: false, error: "Missing parameters: school_id and user_id are required" }, status: :bad_request
      end
    
      user = User.find_by(id: user_id)
      return render json: { success: false, error: "User not found" }, status: :not_found unless user
    
      conversation = Conversation.find_or_create_by(school_id: school_id, user_id: user_id)
      
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

      # PUT /api/v1/conversations/:id/read
      def read
        # Security: only mark messages not sent by the current actor as read
        # For now, we update all as read in the conversation context
        @conversation.messages.where(is_read: false).update_all(is_read: true)
        render json: { success: true, message: "Messages marked as read" }, status: :ok
      end

      # POST /api/v1/conversations/:id/typing
      def typing
        # In a real app, this might broadcast a "typing" event via ActionCable
        render json: { success: true, message: "Typing event acknowledged" }, status: :ok
      end

      # POST /api/v1/conversations/group_initiation
      def group_initiation
        # Placeholder for group conversation logic
        render json: { success: true, message: "Group initiation not yet implemented" }, status: :not_implemented
      end

      private

      def set_conversation
        # Hierarchical lookup if possible, otherwise direct
        if params[:school_id].present? || params[:schoolId].present?
          sid = params[:school_id] || params[:schoolId]
          @conversation = Conversation.find_by(id: params[:id], school_id: sid)
        elsif params[:user_id].present? || params[:userId].present?
          uid = params[:user_id] || params[:userId]
          @conversation = Conversation.find_by(id: params[:id], user_id: uid)
        else
          @conversation = Conversation.find(params[:id])
        end

        # TODO: Add authorization check based on @decoded_token once fully integrated
        return render json: { success: false, error: "Conversation not found" }, status: :not_found unless @conversation
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Invalid Conversation ID" }, status: :not_found
      end
    end
  end
end
