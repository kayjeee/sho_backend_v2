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
        @prefetched_users = User.in(id: bson_ids(all_participant_ids)).index_by { |u| u.id.to_s }

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

        # ── Guard 2: resolve participant IDs ── accept both User IDs and Teacher IDs
        resolved_p_ids = p_ids.uniq.map do |pid|
          # Direct User ID match check
          user = User.find_by(id: pid) rescue nil
          next user.id.to_s if user

          # Fallback: Parse as a Teacher record identification token
          teacher = Teacher.find_by(id: pid) rescue nil
          if teacher
            linked = User.find_by(id: teacher.user_id) ||
                     User.find_by(auth0_id: teacher.auth0_id)
            next linked.id.to_s if linked
          end
          nil
        end.compact

        if resolved_p_ids.size != p_ids.uniq.size
          missing = p_ids.uniq - resolved_p_ids
          return render json: {
            success: false,
            error:   "Participant(s) not found: #{missing.join(', ')}"
          }, status: :unprocessable_entity
        end

        p_ids = resolved_p_ids

        # Subsequent actions map against the normalized p_ids vector
        target_users = User.where(:id.in => bson_ids(p_ids))

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

      # POST /api/v1/conversations/group_initiation
      def group_initiation
        school_id   = params[:school_id] || params.dig(:conversation, :school_id)
        scope_type  = (params[:scope_type] || params.dig(:conversation, :scope_type)).to_s.downcase
        target_id   = params[:target_id] || params.dig(:conversation, :target_id)
        custom_name = params[:custom_name] || params.dig(:conversation, :group_name)

        school_bson = safe_bson(school_id)

        if school_bson.blank?
          return render json: {
            success: false,
            error:   "Valid school_id is required"
          }, status: :bad_request
        end

        unless %w[broadcast grade classroom].include?(scope_type)
          return render json: {
            success: false,
            error:   "scope_type must be one of: broadcast, grade, classroom"
          }, status: :bad_request
        end

        if target_id.blank?
          return render json: {
            success: false,
            error:   "target_id is required"
          }, status: :bad_request
        end

        calculated_ids =
          participant_ids_for_group_scope(
            school_bson: school_bson,
            scope_type: scope_type,
            target_id:  target_id
          )

        all_participants =
          (calculated_ids + [@current_user.id])
          .map(&:to_s)
          .uniq
          .sort

        conversation = Conversation.create(
          participant_ids: all_participants,
          school_id:       school_bson,
          user_id:         @current_user.id,
          group_name:      custom_name.presence || group_initiation_name(scope_type, target_id, school_bson)
        )

        if conversation.persisted?
          render json: {
            success: true,
            data:    serialize_conversation(conversation),
            message: "Group conversation created successfully"
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
          users        = User.in(id: bson_ids(p_ids))
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

      def safe_bson(id_str)
        BSON::ObjectId.from_string(id_str.to_s)
      rescue
        nil
      end

      def bson_ids(ids)
        Array(ids).map do |id|
          safe_bson(id)
        end.compact
      end

      def participant_ids_for_group_scope(school_bson:, scope_type:, target_id:)
        case scope_type
        when "broadcast"
          User.where(:school_ids.in => [school_bson])
              .any_in(roles: [target_id.to_s.downcase])
              .pluck(:id)
        when "grade"
          parent_user_ids_for_learners(
            learners_for_grade(school_bson, target_id),
            school_bson
          ) + parent_user_ids_for_students(
            students_for_grade(school_bson, target_id),
            school_bson
          )
        when "classroom"
          parent_user_ids_for_learners(
            learners_for_classroom(school_bson, target_id),
            school_bson
          ) + parent_user_ids_for_students(
            students_for_classroom(school_bson, target_id),
            school_bson
          )
        else
          []
        end.compact.map(&:to_s).uniq
      end

      def learners_for_grade(school_bson, target_id)
        grade_targets = grade_target_values(school_bson, target_id)

        Learner.where(school_id: school_bson)
               .where(:gradeId.in => grade_targets)
      end

      def students_for_grade(school_bson, target_id)
        return Student.none unless defined?(Student)

        Student.where(school_id: school_bson, grade: target_id.to_s)
      end

      def learners_for_classroom(school_bson, target_id)
        target_values = [target_id.to_s, safe_bson(target_id)].compact
        classroom_fields = %w[
          classroom_id
          classroomId
          class_id
          classId
          classroom
          class_name
          className
          homeroom
        ]

        conditions = classroom_fields.map do |field|
          { field.to_sym.in => target_values }
        end

        Learner.where(school_id: school_bson).any_of(*conditions)
      end

      def students_for_classroom(school_bson, target_id)
        return Student.none unless defined?(Student)

        target_values = [target_id.to_s, safe_bson(target_id)].compact

        Student.where(school_id: school_bson).any_of(
          { :homeroom.in => target_values },
          { :classroom_id.in => target_values },
          { :classroomId.in => target_values },
          { :class_id.in => target_values },
          { :classId.in => target_values }
        )
      end

      def grade_target_values(school_bson, target_id)
        target_bson = safe_bson(target_id)
        grade_conditions = [
          { name: target_id.to_s },
          { grade_level: target_id.to_s }
        ]

        grade_conditions << { _id: target_bson } if target_bson

        grade_ids =
          Grade.where(school_id: school_bson)
               .any_of(*grade_conditions)
               .pluck(:id)
               .map(&:to_s)

        ([target_id.to_s] + grade_ids).uniq
      end

      def parent_user_ids_for_learners(learners, school_bson)
        parent_refs = learners.map do |learner|
          parent_reference_values(learner.parent_info)
        end

        parent_user_ids_from_refs(parent_refs, school_bson)
      end

      def parent_user_ids_for_students(students, school_bson)
        student_ids = students.pluck(:id)
        emails = students.pluck(:primary_contact_email).compact

        if defined?(Guardian) && student_ids.present?
          emails += Guardian.where(:student_id.in => student_ids).pluck(:email).compact
        end

        parent_user_ids_from_refs([{ emails: emails }], school_bson)
      end

      def parent_reference_values(value, refs = { user_ids: [], auth0_ids: [], emails: [] })
        case value
        when Array
          value.each { |entry| parent_reference_values(entry, refs) }
        when Hash
          value.each do |key, nested_value|
            normalized_key = key.to_s.downcase

            if normalized_key.match?(/\A(user_)?id\z/)
              refs[:user_ids] << nested_value
            elsif normalized_key.include?("auth0")
              refs[:auth0_ids] << nested_value
            elsif normalized_key.include?("email")
              refs[:emails] << nested_value
            else
              parent_reference_values(nested_value, refs)
            end
          end
        end

        refs
      end

      def parent_user_ids_from_refs(ref_sets, school_bson)
        refs = ref_sets.each_with_object({ user_ids: [], auth0_ids: [], emails: [] }) do |set, memo|
          memo[:user_ids].concat(Array(set[:user_ids]))
          memo[:auth0_ids].concat(Array(set[:auth0_ids]))
          memo[:emails].concat(Array(set[:emails]))
        end

        direct_user_ids =
          refs[:user_ids]
          .map { |id| safe_bson(id) }
          .compact

        auth0_ids =
          refs[:auth0_ids]
          .map(&:to_s)
          .map(&:strip)
          .reject(&:blank?)
          .uniq

        emails =
          refs[:emails]
          .map(&:to_s)
          .map(&:strip)
          .reject(&:blank?)
          .flat_map { |email| [email, email.downcase] }
          .uniq

        ids = []

        if direct_user_ids.present?
          ids += User.where(:id.in => direct_user_ids)
                     .any_in(roles: ["parent"])
                     .pluck(:id)
        end

        if auth0_ids.present?
          ids += User.where(:school_ids.in => [school_bson])
                     .any_in(roles: ["parent"])
                     .where(:auth0_id.in => auth0_ids)
                     .pluck(:id)
        end

        if emails.present?
          ids += User.where(:school_ids.in => [school_bson])
                     .any_in(roles: ["parent"])
                     .where(:email.in => emails)
                     .pluck(:id)
        end

        ids.compact.map(&:to_s).uniq
      end

      def group_initiation_name(scope_type, target_id, school_bson)
        case scope_type
        when "broadcast"
          "#{target_id.to_s.titleize} Broadcast"
        when "grade"
          "#{grade_label(school_bson, target_id)} Parents Broadcast"
        when "classroom"
          "#{target_id.to_s.titleize} Parents Broadcast"
        end
      end

      def grade_label(school_bson, target_id)
        target_bson = safe_bson(target_id)
        conditions = [
          { name: target_id.to_s },
          { grade_level: target_id.to_s }
        ]
        conditions << { _id: target_bson } if target_bson

        grade = Grade.where(school_id: school_bson)
                     .any_of(*conditions)
                     .first

        grade&.name.presence || "Grade #{target_id}"
      end

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
          users        = User.in(id: bson_ids(participant_ids))
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
          online_status: user.last_seen_at && user.last_seen_at > 45.seconds.ago ? "online" : "offline"
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
          is_pinned: message.try(:is_pinned) || false,
          starred_by: Array(message.try(:starred_by)).map(&:to_s),
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
