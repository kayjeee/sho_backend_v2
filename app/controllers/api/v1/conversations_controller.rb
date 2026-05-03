module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :authorize
      before_action :set_conversation, only: [:show, :destroy, :read, :participants]

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
        # This also surfaces a clear error if the frontend sends a bad ID
        # rather than silently creating a broken conversation.
        target_users = User.where(:id.in => p_ids)
        if target_users.count != p_ids.uniq.size
          missing = p_ids.uniq - target_users.map { |u| u.id.to_s }
          return render json: {
            success: false,
            error:   "Participant(s) not found: #{missing.join(', ')}"
          }, status: :unprocessable_entity
        end

        # ── Guard 3: self-messaging detection ────────────────────────────────
        # The only participant after deduplication is the current user themselves.
        # We still allow a user to open a "Note to self" conversation by sending
        # their own ID — we just route them to/create that single-participant conv.
        other_ids    = p_ids.map(&:to_s).reject { |id| id == @current_user.id.to_s }
        is_self_conv = other_ids.empty?

        all_participants = (p_ids + [@current_user.id.to_s]).map(&:to_s).uniq.sort

        # ── Guard 4: minimum participants for a normal conversation ──────────
        # A real conversation needs at least 2 distinct users.
        # The only exception we permit is the explicit self-conversation.
        if all_participants.size < 2 && !is_self_conv
          return render json: {
            success: false,
            error:   "A conversation requires at least one other participant"
          }, status: :unprocessable_entity
        end

        # ── Find or create ───────────────────────────────────────────────────
        # Sorted participant list guarantees that the query is deterministic
        # regardless of the order IDs were sent from the client.
        # We only search for existing 1-on-1 or self-conversations.
        # Group conversations (3+ people or named) are always created fresh.
        is_group = all_participants.size > 2 || group_name.present?
        conversation = nil

        unless is_group
          p_key = all_participants.join(',')
          conversation = Conversation.where(
            participants_key: p_key,
            school_id:        school_id,
            group_name:       nil # Don't match named groups when looking for 1-on-1s
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
        affected = @conversation.messages
                                .where(:sender_id.ne => @current_user.id.to_s, read: false)
                                .update_all(read: true)

        render json: {
          success: true,
          message: "Messages marked as read",
          count:   affected
        }, status: :ok
      end

      # GET /api/v1/conversations/:id/participants
      # PUT /api/v1/conversations/:id/participants
      def participants
        if request.get?
          p_ids        = (@conversation.participant_ids || []).map(&:to_s)
          users        = User.in(id: p_ids)
          participants = users.map { |u| serialize_participant(u) }

          return render json: {
            success: true,
            data:    participants
          }, status: :ok
        end

        # Support both direct array and nested conversation param
        new_ids = Array(
          params[:participant_ids] || params.dig(:conversation, :participant_ids)
        ).map(&:to_s).reject(&:blank?)

        if new_ids.blank?
          return render json: {
            success: false,
            error:   "No participants provided"
          }, status: :bad_request
        end

        # ── Guard 1: all requested participants must actually exist ──────────
        target_users = User.where(:id.in => new_ids)
        if target_users.count != new_ids.uniq.size
          missing = new_ids.uniq - target_users.map { |u| u.id.to_s }
          return render json: {
            success: false,
            error:   "Participant(s) not found: #{missing.join(', ')}"
          }, status: :unprocessable_entity
        end

        # Merge new IDs with existing ones — never remove participants via this endpoint
        # unless explicitly requested with replace: true
        merged_ids = if params[:replace] == 'true'
                       new_ids
                     else
                       (@conversation.participant_ids + new_ids).uniq.sort
                     end

        # A school group chat can have unlimited participants —
        # only enforce minimum of 1
        if merged_ids.empty?
          return render json: {
            success: false,
            error:   "Conversation must have at least one participant"
          }, status: :unprocessable_entity
        end

        if @conversation.update(participant_ids: merged_ids)
          render json: {
            success: true,
            data:    serialize_conversation(@conversation),
            message: "Participants updated — #{merged_ids.size} total members"
          }, status: :ok
        else
          render json: {
            success: false,
            errors:  @conversation.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue Mongoid::Errors::DocumentNotFound
        render json: {
          success: false,
          error:   "Conversation not found"
        }, status: :not_found
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

        # Use pre-fetched users if available, otherwise fallback to query
        if @prefetched_users
          participants = participant_ids.map { |id| @prefetched_users[id] }.compact.map { |u| serialize_participant(u) }
        else
          users        = User.in(id: participant_ids)
          participants = users.map { |u| serialize_participant(u) }
        end

        # One query for the last message preview.
        last_msg = conversation.messages.order(created_at: :desc).first

        # Unread: messages from others that haven't been read yet.
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
        # Build full_name from every available field, most-preferred first.
        full_name = safe_read(user, :name).presence ||
                    safe_read(user, :full_name).presence ||
                    [
                      safe_read(user, :first_name),
                      safe_read(user, :last_name)
                    ].compact.reject(&:blank?).join(" ").presence ||
                    "Unknown"

        {
          id:        user.id.to_s,
          name:      full_name,
          full_name: full_name,          # redundant alias — keeps frontend options open
          avatar:    safe_read(user, :avatar) || safe_read(user, :profile_image),
          role:      resolve_role(user),
          online_status: "offline"       # extend with presence tracking later
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
          read:      message.try(:read) || false
        }
      end

      # Builds the conversation display title from the perspective of @current_user.
      # participants is already a plain Array of Hashes — no Mongoid touching here.
      def conversation_title(participants, group_name = nil)
        return group_name if group_name.present?

        others = participants.reject { |p| p[:id] == @current_user.id.to_s }

        return "Note to self" if others.empty?

        if others.size == 1
          others.first[:name]
        elsif others.size <= 3
          others.map { |p| p[:name].split(" ").first }.to_sentence
        else
          first_names = others.take(2).map { |p| p[:name].split(" ").first }
          remaining_count = others.size - 2
          "#{first_names.join(', ')}, and #{remaining_count} others"
        end
      end

      # Resolves a user's role from either a single :role field or a :roles array.
      # Uses safe_read to avoid AttributeNotLoaded for either field.
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