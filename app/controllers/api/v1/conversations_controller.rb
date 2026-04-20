module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:show, :destroy]

      # GET /api/v1/conversations
      def index
        # Scoped strictly to @current_user.id to prevent data leakage
        conversations = Conversation.where(user_id: @current_user.id).order(last_message_at: :desc)

        if params[:school_id].present?
          conversations = conversations.where(school_id: params[:school_id])
        end

        render json: { success: true, data: conversations }, status: :ok
      end

      # GET /api/v1/conversations/:id
      def show
        render json: { success: true, data: @conversation }, status: :ok
      end

      # POST /api/v1/conversations
      def create
        school_id = params.dig(:conversation, :school_id)

        if school_id.blank?
          return render json: {
            success: false,
            error: "Missing parameters: school_id is required"
          }, status: :bad_request
        end

        # For security, we always use the @current_user.id for new conversations
        conversation = Conversation.find_or_create_by(
          school_id: school_id,
          user_id: @current_user.id
        )

        if conversation.persisted?
          render json: {
            success: true,
            data: conversation,
            message: "Conversation created or retrieved"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: conversation.errors.full_messages
          }, status: :unprocessable_entity
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
        # Scoping query to current_user.id
        @conversation = Conversation.find_by(id: params[:id], user_id: @current_user.id)

        unless @conversation
          render json: {
            success: false,
            error: "Conversation not found or access denied"
          }, status: :not_found
        end
      end
    end
  end
end
