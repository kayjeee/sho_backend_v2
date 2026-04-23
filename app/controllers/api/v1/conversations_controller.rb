module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:show, :destroy, :read]

      # GET /api/v1/conversations
      def index
        conversations = Conversation.any_of(
          { user_id: @current_user.id },
          { participant_ids: @current_user.id.to_s }
        ).order(last_message_at: :desc)

        conversations = conversations.where(school_id: params[:school_id]) if params[:school_id].present?

        render json: {
          success: true,
          data: conversations.map { |c| serialize_conversation(c) }
        }, status: :ok
      end

      # GET /api/v1/conversations/:id
      def show
        render json: { success: true, data: serialize_conversation(@conversation) }, status: :ok
      end

      # POST /api/v1/conversations
      def create
        school_id   = params.dig(:conversation, :school_id)
        p_ids       = params[:participant_ids] ||
                      params.dig(:conversation, :participant_ids) || []

        if school_id.blank?
          return render json: {
            success: false,
            error: "Missing parameters: school_id is required"
          }, status: :bad_request
        end

        all_participants = (Array(p_ids).map(&:to_s) + [@current_user.id.to_s]).uniq.sort

        if all_participants.size < 2
          return render json: {
            success: false,
            error: "Cannot create a conversation with only yourself"
          }, status: :unprocessable_entity
        end

        # Find existing conversation with exactly these participants
        conversation = Conversation.where(participant_ids: all_participants).first

        if conversation
          render json: {
            success: true,
            data: serialize_conversation(conversation),
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
              data: serialize_conversation(conversation),
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
        affected = @conversation.messages
                                .where(:sender_id.ne => @current_user.id, read: false)
                                .update_all(read: true)

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

      # ---------------------------------------------------------------
      # Serialize a single conversation with:
      #   - participants: array of { id, name, avatar, role, online_status }
      #   - last_message: { content, sender_id, timestamp }
      #   - unread_count: integer
      # ---------------------------------------------------------------
      def serialize_conversation(conversation)
        # Resolve participant User records in one DB query
        participant_ids = (conversation.participant_ids || []).map(&:to_s)
        users           = User.where(:id.in => participant_ids)
                              .only(:id, :name, :first_name, :last_name, :avatar,
                                    :profile_image, :role, :roles)

        participants = users.map { |u| serialize_participant(u) }

        # Fetch last message (one extra query per conversation — acceptable for now)
        last_msg = conversation.messages.order(created_at: :desc).first

        # Unread count: messages not sent by current user that haven't been read
        unread = conversation.messages
                             .where(:sender_id.ne => @current_user.id.to_s, read: false)
                             .count

        {
          id:              conversation.id.to_s,
          participant_ids: participant_ids,
          participants:    participants,
          school_id:       conversation.school_id&.to_s,
          title:           conversation_title(participants),
          last_message:    last_msg ? serialize_message(last_msg) : nil,
          unread_count:    unread,
          last_message_at: conversation.last_message_at || conversation.created_at,
          updated_at:      conversation.updated_at,
          created_at:      conversation.created_at
        }
      end

      def serialize_participant(user)
        name = user.name.presence ||
               [user.first_name, user.last_name].compact.join(" ").presence ||
               "Unknown"

        role = resolve_role(user)

        {
          id:            user.id.to_s,
          name:          name,
          avatar:        user.try(:avatar) || user.try(:profile_image),
          role:          role,
          online_status: "offline"   # extend later with presence tracking
        }
      end

      def serialize_message(message)
        {
          id:         message.id.to_s,
          content:    message.content.presence || message.try(:body) || message.try(:text) || "",
          sender_id:  message.sender_id.to_s,
          timestamp:  message.created_at,
          read:       message.try(:read) || false
        }
      end

      # Build a human-readable title from participants, excluding current user
      def conversation_title(participants)
        others = participants.reject { |p| p[:id] == @current_user.id.to_s }
        return "Note to self" if others.empty?

        if others.size == 1
          others.first[:name]
        elsif others.size == 2
          others.map { |p| p[:name].split(" ").first }.join(" & ")
        else
          "#{others.first[:name].split(' ').first} & #{others.size - 1} others"
        end
      end

      def resolve_role(user)
        # Handle both a single `role` field and a `roles` array
        roles_list = Array(user.try(:roles)).map(&:to_s)
        single     = user.try(:role).to_s

        return "admin"    if roles_list.include?("admin")    || single == "admin"
        return "teacher"  if roles_list.include?("teacher")  || single == "teacher"
        return "parent"   if roles_list.include?("parent")   || single == "parent"
        return "principal" if roles_list.include?("principal") || single == "principal"

        "staff"
      end
    end
  end
end