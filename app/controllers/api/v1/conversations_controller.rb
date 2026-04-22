module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:show, :destroy, :read]

      # GET /api/v1/conversations
      def index
        # Scoped strictly to @current_user.id to prevent data leakage
        # We search for conversations where the current user is a participant
        conversations = Conversation.any_of(
          { user_id: @current_user.id },
          { participant_ids: @current_user.id.to_s }
        ).order(last_message_at: :desc)

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
        p_ids = params[:participant_ids] || params.dig(:conversation, :participant_ids) || []

        if school_id.blank?
          return render json: {
            success: false,
            error: "Missing parameters: school_id is required"
          }, status: :bad_request
        end

        # Ensure current user is in participants
        all_participants = (Array(p_ids).map(&:to_s) + [@current_user.id.to_s]).uniq.sort

        # Prevent messaging oneself (if there are no other participants)
        if all_participants.size < 2
           return render json: {
             success: false,
             error: "Cannot create a conversation with only yourself"
           }, status: :unprocessable_entity
        end

        # Use participant_ids for uniqueness check.
        # We sort them to ensure deterministic search.
        conversation = Conversation.where(participant_ids: all_participants).first

        if conversation
          render json: {
            success: true,
            data: conversation,
            message: "Existing conversation retrieved"
          }, status: :ok
        else
          conversation = Conversation.create(
            participant_ids: all_participants,
            school_id: school_id,
            user_id: @current_user.id
          )

          if conversation.persisted?
            render json: {
              success: true,
              data: conversation,
              message: "Conversation created successfully"
            }, status: :ok
          else
            render json: {
              success: false,
              errors: conversation.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end

      # PUT /api/v1/conversations/:id/read
      def read
        # Mark all messages as read where the sender is NOT the current user
        # This assumes Message model has 'read' field and 'sender_id'
        affected = @conversation.messages.where(:sender_id.ne => @current_user.id, read: false).update_all(read: true)

        render json: {
          success: true,
          message: "Messages marked as read",
          count: affected
        }, status: :ok
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
        @conversation = Conversation.any_of(
          { user_id: @current_user.id },
          { participant_ids: @current_user.id.to_s }
        ).find_by(id: params[:id])

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
