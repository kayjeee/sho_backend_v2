# frozen_string_literal: true

module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:show, :destroy, :read, :participants, :typing]

      # GET /api/v1/conversations
      def index
        conversations = Conversation.any_of(
          { user_id: @current_user.id },
          { participant_ids: @current_user.id.to_s }
        ).order(updated_at: :desc)

        conversations = conversations.where(school_id: params[:school_id]) if params[:school_id].present?

        # Pre-fetch all participants to avoid N+1 queries during serialization
        all_participant_ids = conversations.pluck(:participant_ids).flatten.uniq
        @prefetched_users = User.in(id: all_participant_ids).index_by { |u| u.id.to_s }

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
        school_id  = params.dig(:conversation, :school_id)
        group_name = params.dig(:conversation, :group_name) || params[:group_name]
        p_ids      = Array(
          params[:participant_ids] || params.dig(:conversation, :participant_ids) || []
        ).map(&:to_s).reject(&:blank?)

        # ── Guard 1: school_id is mandatory ─────────────────────────────────
        if school_id.blank?
          return render json: {
            success: false,
            error:   "school_id is required"
          }, status: :bad_request
        end

        # ── Guard 2: all requested participants must actually exist ──────────
        target_users = User.where(:id.in => p_ids)
        if target_users.count != p_ids.uniq.size
          missing = p_ids.uniq - target_users.map { |u| u.id.to_s }
          return render json: {
            success: false,
            error:   "Participant(s) not found: #{missing.join(', ')}"
          }, status: :unprocessable_entity
        end

        # ── Guard 3: self-messaging detection ────────────────────────────────
        other_ids    = p_ids.map(&:to_s).reject { |id| id == @current_user.id.to_s }
        is_self_conv = other_ids.empty?

        all_participants = (p_ids + [@current_user.id.to_s]).map(&:to_s).uniq.sort

        # ── Guard 4: minimum participants for a normal conversation ──────────
        if all_participants.size < 2 && !is_self_conv
          return render json: {
            success: false,
            error:   "A conversation requires at least one other participant"
          }, status: :unprocessable_entity
        end

        # ── Find or create ───────────────────────────────────────────────────
        is_group = all_participants.size > 2 || group_name.present?
        conversation = nil

        unless is_group
          p_key = all_participants.join(',')
          conversation = Conversation.where(
            participants_key: p_key,
            school_id:        school_id,
            group_name:       nil
          ).first
        end

        if conversation
          return render json: {
            success: true,
            data:    serialize_conversation(conversation),
            message: is_self_conv ? "Self-conversation retrieved" : "Existing conversation retrieved"
          }, status: :ok
        end

        conversation = Conversation.create(
          participant_ids: all_participants,
          school_id:       school_id,
          user_id:         @current_user.id,
          group_name:      group_name
        )

        if conversation.persisted?
          render json: {
            success: true,
            data:    serialize_conversation(conversation),
            message: is_self_conv ? "Self-conversation created" : "Conversation created successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors:  conversation.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/conversations/:id/read
      def read
        affected = Message.mark_as_read!(@conversation, @current_user)

        render json: {
          success: true,
          message: "Messages marked as read",
          count:   affected
        }, status: :ok
      end

      # POST /api/v1/conversations/:id/typing
      def typing
        MessagesChannel.broadcast_to(
          @conversation,
          {
            type:      "typing",
            user_id:   @current_user.id.to_s,
            name:      @current_user.name,
            is_typing: params[:is_typing]
          }
        )

        head :ok # no body — fastest possible response for a fire-and-forget endpoint
      end

      # GET /api/v1/conversations/:id/participants
      # PUT /api/v1/conversations/:id/participants
      def participants
        if request.get?
          p_ids        = (@conversation.participant_ids || []).map(&:to_s)
          users        = User.in(id: p_ids)
          participants = users.map { |u| serialize_participant(u) }
          return render json: { success: true, data: participants }, status: :ok
        end

        new_ids = params[:participant_ids] || params.dig(:conversation, :participant_ids)

        if @conversation.update(participant_ids: new_ids)
          render json: {
            success: true,
            data:    serialize_conversation(@conversation)
          }, status: :ok
        else
          render json: {
            success: false,
            errors:  @conversation.errors.full_messages
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
        @conversation = Conversation.any_of(
          { user_id: @current_user.id },
          { participant_ids: @current_user.id.to_s }
        ).find_by(id: params[:id])

        unless @conversation
          render json: {
            success: false,
            error:   "Conversation not found or access denied"
          }, status: :not_found
        end
      end

      # -----------------------------------------------------------------------
      # Serialize a single Conversation to a plain Ruby Hash.
      #
      # Returns:
      #   id, title, participant_ids, participants[], school_id,
      #   last_message{}, unread_count, last_message_at, updated_at, created_at
      #
      # ⚠️  NEVER use .only() or .without() on the User query here.
      #     Mongoid raises AttributeNotLoaded when any callback or embedded
      #     association (e.g. onboarding_status) touches an excluded field.
      #     Loading the full document is cheaper than the debugging cost.
      # -----------------------------------------------------------------------
      def serialize_conversation(conversation)
        participant_ids = (conversation.participant_ids || []).map(&:to_s)

        if @prefetched_users
          participants = participant_ids
            .map { |id| @prefetched_users[id] }
            .compact
            .map { |u| serialize_participant(u) }
        else
          users        = User.in(id: participant_ids)
          participants = users.map { |u| serialize_participant(u) }
        end

        last_msg = conversation.messages.order(created_at: :desc).first

        unread = conversation.messages
                             .where(:sender_id.ne => @current_user.id.to_s, read: false)
                             .count

        {
          id:              conversation.id.to_s,
          title:           conversation_title(participants, conversation.group_name),
          group_name:      conversation.group_name,
          participant_ids: participant_ids,
          participants:    participants,
          school_id:       conversation.school_id&.to_s,
          last_message:    last_msg ? serialize_message(last_msg) : nil,
          unread_count:    unread,
          last_message_at: conversation.try(:last_message_at) || conversation.updated_at || conversation.created_at,
          updated_at:      conversation.updated_at,
          created_at:      conversation.created_at
        }
      end

      # Converts a User document to a plain hash for inclusion in the response.
      # Uses safe_read throughout to avoid AttributeNotLoaded on any field.
      def serialize_participant(user)
        full_name =
          safe_read(user, :name).presence ||
          safe_read(user, :full_name).presence ||
          [
            safe_read(user, :first_name),
            safe_read(user, :last_name)
          ].compact.reject(&:blank?).join(" ").presence ||
          "Unknown"

        {
          id:           user.id.to_s,
          name:         full_name,
          full_name:    full_name,
          avatar:       safe_read(user, :avatar) || safe_read(user, :profile_image),
          role:         resolve_role(user),
          online_status: user.last_seen_at && user.last_seen_at > 30.seconds.ago ? "online" : "offline"
        }
      end

      # Raw attribute access — bypasses all Mongoid accessor magic and
      # embedded-document auto-loading. Returns nil on any unloaded field.
      def safe_read(user, field)
        user.read_attribute(field)
      rescue Mongoid::Errors::AttributeNotLoaded
        nil
      end

      def serialize_message(message)
        {
          id:        message.id.to_s,
          content:   message.try(:content).presence ||
                     message.try(:body).presence ||
                     message.try(:text).presence || "",
          sender_id: message.sender_id.to_s,
          timestamp: message.created_at,
          read:      message.try(:read) || false,
          status:    message.try(:status) || "sent",
          reactions: message.try(:reactions) || []
        }
      end

      # Builds the conversation display title from the perspective of @current_user.
      def conversation_title(participants, group_name = nil)
        return group_name if group_name.present?

        others = participants.reject { |p| p[:id] == @current_user.id.to_s }

        return "Note to self" if others.empty?

        if others.size == 1
          others.first[:name]
        elsif others.size <= 3
          others.map { |p| p[:name].split(" ").first }.to_sentence
        else
          first_names    = others.take(2).map { |p| p[:name].split(" ").first }
          remaining_count = others.size - 2
          "#{first_names.join(', ')}, and #{remaining_count} others"
        end
      end

      # Resolves a user's role from either a single :role field or a :roles array.
      def resolve_role(user)
        roles_list = Array(safe_read(user, :roles)).map(&:to_s)
        single     = safe_read(user, :role).to_s

        return "admin"     if roles_list.include?("admin")     || single == "admin"
        return "teacher"   if roles_list.include?("teacher")   || single == "teacher"
        return "parent"    if roles_list.include?("parent")    || single == "parent"
        return "principal" if roles_list.include?("principal") || single == "principal"

        "staff"
      end
    end
  end
end
