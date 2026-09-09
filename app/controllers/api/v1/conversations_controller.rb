module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :set_conversation, only: [:show, :destroy]

      # GET /api/v1/conversations
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_id     = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]
        user_id       = raw_params[:user_id] || raw_params["user_id"] || raw_params[:userId] || raw_params["userId"]
        scope_type    = raw_params[:scope_type] || raw_params["scope_type"] || raw_params[:scopeType] || raw_params["scopeType"]
        scope_id      = raw_params[:scope_id] || raw_params["scope_id"] || raw_params[:scopeId] || raw_params["scopeId"] || raw_params[:grade_id] || raw_params["grade_id"]
        academic_year = raw_params[:academic_year] || raw_params["academic_year"] || raw_params[:academicYear] || raw_params["academicYear"]
        term_id       = raw_params[:term_id] || raw_params["term_id"] || raw_params[:termId] || raw_params["termId"]

        scope = Conversation.all

        if school_id.present?
          s_bson = BSON::ObjectId.legal?(school_id.to_s) ? BSON::ObjectId.from_string(school_id.to_s) : school_id
          scope = scope.where(school_id: s_bson)
        end

        if user_id.present?
          user_obj = find_user(user_id)
          u_bson = user_obj ? user_obj.id : (BSON::ObjectId.legal?(user_id.to_s) ? BSON::ObjectId.from_string(user_id.to_s) : user_id)
          u_str = user_obj ? user_obj.id.to_s : user_id.to_s

          scope = scope.any_of(
            { user_id: u_bson },
            { participant_ids: u_str }
          )
        end

        scope = scope.by_scope_type(scope_type) if scope_type.present?
        scope = scope.by_scope_id(scope_id) if scope_id.present?
        scope = scope.by_academic_year(academic_year) if academic_year.present?
        scope = scope.by_term_id(term_id) if term_id.present?

        if school_id.blank? && user_id.blank? && scope_type.blank?
          return render json: { success: false, error: "Missing school_id or user_id" }, status: :bad_request
        end

        conversations = scope.order(updated_at: :desc).to_a

        render json: { success: true, total: conversations.size, data: conversations.map(&:as_json) }, status: :ok
      rescue => e
        render_exception("ConversationsController#index", e)
      end

      # GET /api/v1/conversations/:id
      def show
        requesting_user_id = params[:requesting_user_id] || params[:user_id] || params[:userId]
        if requesting_user_id.present?
          req_user = find_user(requesting_user_id)
          req_uid = req_user ? req_user.id.to_s : requesting_user_id.to_s
          unless @conversation.participant?(req_uid)
            return render json: { success: false, error: "Forbidden: Not a participant in this conversation" }, status: :forbidden
          end
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
        user_ident = conv_params[:user_id] || conv_params["user_id"] || conv_params[:userId] || conv_params["userId"]
        scope_type = (conv_params[:scope_type] || conv_params["scope_type"] || conv_params[:scopeType] || conv_params["scopeType"] || 'individual').to_s.downcase
        scope_id   = conv_params[:scope_id] || conv_params["scope_id"] || conv_params[:scopeId] || conv_params["scopeId"]
        title      = conv_params[:title] || conv_params["title"]

        if school_id.blank?
          return render json: { success: false, error: "Missing parameter: school_id is required" }, status: :bad_request
        end

        if scope_type == 'individual'
          if user_ident.blank?
            return render json: { success: false, error: "Missing parameter: user_id is required for individual conversation" }, status: :bad_request
          end

          user = find_user(user_ident)
          return render json: { success: false, error: "User not found" }, status: :not_found unless user

          conversation = Conversation.find_or_create_by_school_and_user(school_id, user)

          if conversation&.persisted?
            render json: { success: true, data: conversation, message: "Conversation created or retrieved" }, status: :ok
          else
            render json: { success: false, errors: conversation ? conversation.errors.full_messages : ["Failed to create conversation"] }, status: :unprocessable_entity
          end
        else
          requesting_user = find_user(user_ident)
          requesting_id = requesting_user&.id&.to_s || user_ident.to_s

          participant_uids = GroupConversationService.resolve_participants(school_id, scope_type, scope_id, requesting_id)

          if participant_uids.empty?
            return render json: { success: false, error: "No eligible participants found for group conversation" }, status: :unprocessable_entity
          end

          curr_term = Term.current_for_school(school_id)
          acad_year = curr_term ? curr_term.academic_year.to_s : Date.current.year.to_s
          term_id_str = curr_term ? curr_term.id.to_s : nil

          auto_title = title.presence || generate_group_title(scope_type, scope_id, curr_term)

          s_bson = BSON::ObjectId.legal?(school_id.to_s) ? BSON::ObjectId.from_string(school_id.to_s) : school_id

          conversation = Conversation.create(
            school_id: s_bson,
            user_id: requesting_user&.id,
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
        if @conversation.destroy
          render json: { success: true, message: "Conversation deleted successfully" }, status: :ok
        else
          render json: { success: false, error: "Failed to delete conversation" }, status: :unprocessable_entity
        end
      end

      private

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
