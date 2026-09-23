module Api
  module V1
    class ConversationsController < ApplicationController
      # TEMPORARILY DISABLED MANDATORY TOKEN AUTH FOR TESTING — SEE [TEMPORARY-TESTING-BYPASS]
      # before_action :authenticate_user!
      before_action :set_current_user
      before_action :set_conversation, only: [:show, :destroy, :remove_participant, :leave]

      # GET /api/v1/conversations
      def index
        # When @current_user cannot be resolved, return an empty result set rather than an unscoped school query
        if @current_user.nil?
          return render json: { success: true, total: 0, data: [] }, status: :ok
        end

        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_id     = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]
        scope_type    = raw_params[:scope_type] || raw_params["scope_type"] || raw_params[:scopeType] || raw_params["scopeType"]
        scope_id      = raw_params[:scope_id] || raw_params["scope_id"] || raw_params[:scopeId] || raw_params["scopeId"] || raw_params[:grade_id] || raw_params["grade_id"]
        academic_year = raw_params[:academic_year] || raw_params["academic_year"] || raw_params[:academicYear] || raw_params["academicYear"]
        term_id       = raw_params[:term_id] || raw_params["term_id"] || raw_params[:termId] || raw_params["termId"]

        scope = Conversation.all

        if school_id.present?
          s_bson = BSON::ObjectId.legal?(school_id.to_s) ? BSON::ObjectId.from_string(school_id.to_s) : school_id
          scope = scope.where(school_id: s_bson)
        end

        u_bson = @current_user.id
        u_str = @current_user.id.to_s
        u_auth0 = @current_user.auth0_id
        user_uids = [u_str, u_auth0].compact.uniq

        # Membership rule: strictly participant_ids membership (or legacy 1:1 where user_id == @current_user.id)
        scope = scope.any_of(
          { :participant_ids.in => user_uids },
          { scope_type: 'individual', user_id: u_bson }
        )

        scope = scope.by_scope_type(scope_type) if scope_type.present?
        scope = scope.by_scope_id(scope_id) if scope_id.present?
        scope = scope.by_academic_year(academic_year) if academic_year.present?
        scope = scope.by_term_id(term_id) if term_id.present?

        conversations = scope.order(updated_at: :desc).to_a

        render json: { success: true, total: conversations.size, data: conversations.map(&:as_json) }, status: :ok
      rescue => e
        render_exception("ConversationsController#index", e)
      end

      # GET /api/v1/conversations/:id
      def show
        if @current_user.nil?
          return render json: { success: false, error: "Unauthorized: User identification required" }, status: :unauthorized
        end

        unless @conversation.participant?(@current_user)
          return render json: { success: false, error: "Forbidden: Not a participant in this conversation" }, status: :forbidden
        end

        render json: { success: true, data: @conversation.as_json }, status: :ok
      end

      # POST /api/v1/conversations
      def create
        raw_payload = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        conv_params = raw_payload[:conversation] || raw_payload["conversation"] || raw_payload

        school_id  = conv_params[:school_id] || conv_params["school_id"] || conv_params[:schoolId] || conv_params["schoolId"]
        user_ident = conv_params[:user_id] || conv_params["user_id"] || conv_params[:userId] || conv_params["userId"] || conv_params[:recipient_id] || conv_params[:target_user_id]
        scope_type = (conv_params[:scope_type] || conv_params["scope_type"] || conv_params[:scopeType] || conv_params["scopeType"] || 'individual').to_s.downcase
        scope_id   = conv_params[:scope_id] || conv_params["scope_id"] || conv_params[:scopeId] || conv_params["scopeId"]
        title      = conv_params[:title] || conv_params["title"]

        if school_id.blank?
          return render json: { success: false, error: "Missing parameter: school_id is required" }, status: :bad_request
        end

        if scope_type == 'individual'
          target_user = user_ident.present? ? find_user(user_ident) : @current_user
          if user_ident.present? && target_user.nil?
            return render json: { success: false, error: "User not found" }, status: :not_found
          end

          unless target_user
            return render json: { success: false, error: "Missing parameter: user_id is required for individual conversation" }, status: :bad_request
          end

          conversation = Conversation.find_or_create_by_school_and_user(school_id, target_user)

          if conversation&.persisted?
            acting_id = @current_user&.id&.to_s || target_user.id.to_s
            p_add = [acting_id, target_user.id.to_s].uniq
            conversation.add_to_set(participant_ids: p_add)
            conversation.reload

            render json: { success: true, data: conversation, message: "Conversation created or retrieved" }, status: :ok
          else
            render json: { success: false, errors: conversation ? conversation.errors.full_messages : ["Failed to create conversation"] }, status: :unprocessable_entity
          end
        else
          acting_id = @current_user&.id&.to_s || user_ident.to_s
          participant_uids = GroupConversationService.resolve_participants(school_id, scope_type, scope_id, acting_id)
          participant_uids = (participant_uids + [acting_id]).compact.reject(&:blank?).uniq

          if participant_uids.empty?
            return render json: { success: false, error: "No eligible participants found for group conversation" }, status: :unprocessable_entity
          end

          curr_term = Term.current_for_school(school_id)
          acad_year = curr_term ? curr_term.academic_year.to_s : Date.current.year.to_s
          term_id_str = curr_term ? curr_term.id.to_s : nil

          auto_title = title.presence || generate_group_title(scope_type, scope_id, curr_term)

          s_bson = BSON::ObjectId.legal?(school_id.to_s) ? BSON::ObjectId.from_string(school_id.to_s) : school_id
          owner_id = @current_user&.id || find_user(user_ident)&.id

          conversation = Conversation.create(
            school_id: s_bson,
            user_id: owner_id,
            scope_type: scope_type,
            scope_id: scope_id.to_s,
            participant_ids: participant_uids,
            academic_year: acad_year,
            term_id: term_id_str,
            title: auto_title
          )

          if conversation.persisted?
            render json: { success: true, data: conversation, message: "Group conversation created successfully" }, status: :created
          else
            render json: { success: false, errors: conversation.errors.full_messages }, status: :unprocessable_entity
          end
        end
      rescue => e
        render_exception("ConversationsController#create", e)
      end

      # DELETE /api/v1/conversations/:id
      def destroy
        if @current_user.nil?
          return render json: { success: false, error: "Unauthorized: User identification required" }, status: :unauthorized
        end

        unless @conversation.participant?(@current_user) || school_admin?(@current_user, @conversation.school_id)
          return render json: { success: false, error: "Forbidden: Not authorized to delete this conversation" }, status: :forbidden
        end

        if @conversation.destroy
          render json: { success: true, message: "Conversation deleted successfully" }, status: :ok
        else
          render json: { success: false, error: "Failed to delete conversation" }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/conversations/:id/remove_participant
      def remove_participant
        raw_payload = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        target_id = raw_payload[:target_user_id] || raw_payload["target_user_id"] || raw_payload[:targetUserId] || raw_payload["targetUserId"] || raw_payload[:target_id]

        if target_id.blank?
          return render json: { success: false, error: "Missing parameter: target_user_id is required" }, status: :bad_request
        end

        if @current_user.nil?
          return render json: { success: false, error: "Unauthorized: User identification required" }, status: :unauthorized
        end

        unless school_admin?(@current_user, @conversation.school_id)
          return render json: { success: false, error: "Forbidden: Requester is not an admin for this school" }, status: :forbidden
        end

        target_user = find_user(target_id)
        target_uids = [target_user&.id&.to_s, target_user&.auth0_id, target_id.to_s].compact.uniq

        unless target_uids.any? { |uid| @conversation.participant?(uid) }
          return render json: { success: false, error: "Target user is not a participant in this conversation" }, status: :unprocessable_entity
        end

        @conversation.pull_all(participant_ids: target_uids)
        @conversation.reload

        broadcast_conversation_update(@conversation, "participant_removed", target_user&.id&.to_s || target_id.to_s)

        render json: { success: true, message: "Participant removed successfully", data: @conversation.as_json }, status: :ok
      rescue => e
        render_exception("ConversationsController#remove_participant", e)
      end

      # POST /api/v1/conversations/:id/leave
      def leave
        if @current_user.nil?
          return render json: { success: false, error: "Missing parameter: user_id is required" }, status: :bad_request
        end

        user_uids = [@current_user.id.to_s, @current_user.auth0_id].compact.uniq

        unless user_uids.any? { |uid| @conversation.participant?(uid) }
          return render json: { success: false, error: "User is not a participant in this conversation" }, status: :unprocessable_entity
        end

        @conversation.pull_all(participant_ids: user_uids)
        @conversation.reload

        broadcast_conversation_update(@conversation, "participant_left", @current_user.id.to_s)

        render json: { success: true, message: "Successfully left the conversation", data: @conversation.as_json }, status: :ok
      rescue => e
        render_exception("ConversationsController#leave", e)
      end

      private

      # TEMPORARILY DISABLED MANDATORY TOKEN AUTH FOR TESTING — SEE [TEMPORARY-TESTING-BYPASS]
      # Resolves @current_user from Auth0 token if valid, falling back to params[:user_id] / params[:userId] if unauthenticated or error without calling render.
      def set_current_user
        auth_header = request.headers['Authorization']
        if auth_header.present?
          header_elements = auth_header.to_s.split
          if header_elements.length == 2 && header_elements.first.downcase == 'bearer'
            token = header_elements.last
            begin
              validation_response = Auth0Client.validate_token(token)
              if validation_response && validation_response.error.nil? && validation_response.decoded_token
                @decoded_token = validation_response.decoded_token
                auth0_sub = nil
                if @decoded_token.respond_to?(:token) && @decoded_token.token.is_a?(Array) && @decoded_token.token[0].is_a?(Hash)
                  auth0_sub = @decoded_token.token[0]['sub'] || @decoded_token.token[0][:sub]
                elsif @decoded_token.is_a?(Hash)
                  auth0_sub = @decoded_token['sub'] || @decoded_token[:sub]
                end
                @current_user = find_user(auth0_sub) if auth0_sub.present?
              end
            rescue => e
              Rails.logger.warn "⚠️ Auth0Client token validation error: #{e.message}"
            end
          end
        end

        if @current_user.nil?
          raw_payload = begin
            params.to_unsafe_h
          rescue
            params.to_h
          end

          conv_payload = raw_payload[:conversation] || raw_payload["conversation"] || raw_payload
          msg_payload  = raw_payload[:message] || raw_payload["message"] || raw_payload

          user_ident = raw_payload[:user_id] || raw_payload["user_id"] ||
                       raw_payload[:userId] || raw_payload["userId"] ||
                       raw_payload[:requesting_user_id] || raw_payload["requesting_user_id"] ||
                       raw_payload[:requester_id] || raw_payload["requester_id"] ||
                       conv_payload[:user_id] || conv_payload["user_id"] ||
                       conv_payload[:userId] || conv_payload["userId"] ||
                       conv_payload[:recipient_id] || conv_payload["recipient_id"] ||
                       conv_payload[:target_user_id] || conv_payload["target_user_id"] ||
                       msg_payload[:user_id] || msg_payload["user_id"] ||
                       msg_payload[:userId] || msg_payload["userId"]

          @current_user = find_user(user_ident) if user_ident.present?
        end
      end

      def set_conversation
        @conversation = Conversation.find(params[:id]) rescue nil
        unless @conversation
          return render json: { success: false, error: "Conversation not found" }, status: :not_found
        end
      end

      def find_user(identifier)
        return nil if identifier.blank?

        ident_str = identifier.to_s.strip

        if BSON::ObjectId.legal?(ident_str)
          u = User.where(_id: BSON::ObjectId.from_string(ident_str)).first
          return u if u
        end

        User.where(auth0_id: ident_str).first
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
        User.where(auth0_id: identifier.to_s).first
      end

      def school_admin?(user, school_id)
        return false unless user.present?
        roles_lower = Array(user.roles).map(&:to_s).map(&:downcase)
        return false unless roles_lower.include?('admin')

        s_str = school_id.to_s
        user_school_ids = Array(user.school_ids).map(&:to_s)
        return true if user_school_ids.include?(s_str)

        s_bson = BSON::ObjectId.legal?(s_str) ? BSON::ObjectId.from_string(s_str) : nil
        school = School.where(:id.in => [s_str, s_bson].compact).first
        return false unless school

        return true if school.user_id.to_s == user.id.to_s || school.school_created_by.to_s == user.id.to_s

        if school.adminUsers.present? && school.adminUsers.is_a?(Array)
          admin_emails = school.adminUsers.map { |a| a[:email] || a['email'] }.compact
          return true if admin_emails.include?(user.email)
        end

        false
      end

      def broadcast_conversation_update(conversation, event, target_user_id)
        channel_name = "conversation_#{conversation.id}"
        payload = {
          event: event,
          conversation_id: conversation.id.to_s,
          target_user_id: target_user_id,
          participant_ids: conversation.participant_ids,
          updated_at: Time.current.iso8601
        }
        if defined?(ActionCable) && ActionCable.respond_to?(:server) && ActionCable.server.present?
          ActionCable.server.broadcast(channel_name, payload)
        end
      rescue => e
        Rails.logger.warn "⚠️ ActionCable broadcast failed: #{e.message}"
      end

      def generate_group_title(scope_type, scope_id, term)
        term_prefix = term ? "#{term.name} " : ""
        case scope_type
        when 'class'
          sc = SchoolClass.find(scope_id) rescue nil
          "#{term_prefix}Class #{sc&.name || scope_id}"
        when 'grade'
          g = Grade.find(scope_id) rescue nil
          "#{term_prefix}#{g&.name || scope_id}"
        when 'school'
          "#{term_prefix}Whole School Group"
        when 'teachers'
          "#{term_prefix}All Teachers Group"
        when 'self'
          "Personal Notes"
        else
          "Group Conversation"
        end
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end