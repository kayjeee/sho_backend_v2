# frozen_string_literal: true

module Api
  module V1
    class MessagesController < ApplicationController
      before_action :authorize

      before_action :set_conversation,
                    only: %i[index create react search]

      before_action :set_message,
                    only: [:react]

      # =========================================================
      # GET /api/v1/conversations/:conversation_id/messages
      # =========================================================
      def index
        Rails.logger.info(
          "[MessagesController#index] conversation_id=#{@conversation.id} " \
          "current_user=#{@current_user.id}"
        )

        Message.mark_as_delivered!(@conversation, @current_user)

        messages = @conversation.messages.order(created_at: :asc)

        render json: {
          success: true,
          data: messages.map { |message| serialize_message(message) }
        }, status: :ok
      end

      # =========================================================
      # GET /api/v1/conversations/:conversation_id/messages/search?q=hello
      # =========================================================
      def search
        q = params[:q].to_s.strip

        Rails.logger.info(
          "[MessagesController#search] " \
          "conversation_id=#{@conversation.id} q=#{q.inspect}"
        )

        return render json: {
          success: true,
          data: []
        }, status: :ok if q.blank?

        begin
          messages =
            if q.length >= 3
              @conversation.messages
                           .where("$text" => { "$search" => q })
                           .order(created_at: :desc)
                           .limit(50)
            else
              @conversation.messages
                           .where(content: /#{Regexp.escape(q)}/i)
                           .order(created_at: :desc)
                           .limit(50)
            end

          render json: {
            success: true,
            data: messages.map { |message| serialize_message(message) }
          }, status: :ok

        rescue Mongo::Error::OperationFailure => e
          Rails.logger.warn(
            "[MessagesController#search] Text search failed: #{e.message}"
          )

          messages = @conversation.messages
                                  .where(content: /#{Regexp.escape(q)}/i)
                                  .order(created_at: :desc)
                                  .limit(50)

          render json: {
            success: true,
            data: messages.map { |message| serialize_message(message) }
          }, status: :ok
        end
      end

      # =========================================================
      # POST /api/v1/conversations/:conversation_id/messages
      # =========================================================
      def create
        Rails.logger.info(
          "[MessagesController#create] START " \
          "conversation_id=#{params[:conversation_id]} " \
          "current_user=#{@current_user.id}"
        )

        Rails.logger.info(
          "[MessagesController#create] RAW PARAMS=#{params.to_unsafe_h.inspect}"
        )

        sender = find_sender
        return unless sender

        message = @conversation.messages.build(message_params)

        Rails.logger.info(
          "[MessagesController#create] message_params=#{message_params.inspect}"
        )

        # =========================================================
        # ASSIGN SENDER
        # =========================================================
        if sender.is_a?(User)
          message.sender = sender
          message.sender_id = sender.id.to_s
          message.user_id = sender.id.to_s
        end

        # =========================================================
        # SCHOOL CONTEXT
        # =========================================================
        if params.dig(:message, :school_id).present?
          begin
            school = School.find(params.dig(:message, :school_id))
            message.school = school
            message.school_id = school.id.to_s
          rescue Mongoid::Errors::DocumentNotFound
            Rails.logger.warn(
              "[MessagesController#create] School not found: " \
              "#{params.dig(:message, :school_id)}"
            )
          end
        end

        # =========================================================
        # NORMALIZE ATTACHMENT TYPE
        # =========================================================
        if message.attachment_type.present?
          original_type = message.attachment_type

          message.attachment_type =
            normalize_attachment_type(message.attachment_type)

          Rails.logger.info(
            "[MessagesController#create] attachment_type normalized " \
            "#{original_type.inspect} -> #{message.attachment_type.inspect}"
          )
        end

        Rails.logger.info(
          "[MessagesController#create] BEFORE SAVE " \
          "content=#{message.content.inspect} " \
          "attachment_url_present=#{message.attachment_url.present?} " \
          "attachment_type=#{message.attachment_type.inspect} " \
          "sender_id=#{message.sender_id.inspect} " \
          "conversation_id=#{message.conversation_id.inspect}"
        )

        # =========================================================
        # SAVE
        # =========================================================
        if message.save
          Rails.logger.info(
            "[MessagesController#create] SUCCESS message_id=#{message.id}"
          )

          @conversation.touch_last_message_at!

          render json: {
            success: true,
            data: serialize_message(message),
            message: "Message created successfully"
          }, status: :created
        else
          Rails.logger.error(
            "[MessagesController#create] FAILED " \
            "errors=#{message.errors.full_messages.inspect}"
          )

          Rails.logger.error(
            "[MessagesController#create] attachment_type=#{message.attachment_type.inspect}"
          )

          Rails.logger.error(
            "[MessagesController#create] attachment_url=#{message.attachment_url.inspect}"
          )

          Rails.logger.error(
            "[MessagesController#create] sender_id=#{message.sender_id.inspect}"
          )

          Rails.logger.error(
            "[MessagesController#create] conversation=#{message.conversation.inspect}"
          )

          render json: {
            success: false,
            errors: message.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # =========================================================
      # POST REACTION
      # =========================================================
      def react
        emoji = params[:emoji] || params.dig(:reaction, :emoji)

        if emoji.blank?
          return render json: {
            success: false,
            error: "emoji is required"
          }, status: :bad_request
        end

        Rails.logger.info(
          "[MessagesController#react] message_id=#{@message.id} " \
          "emoji=#{emoji} user=#{@current_user.id}"
        )

        @message.toggle_reaction!(emoji, @current_user.id)

        render json: {
          success: true,
          data: MessageSerializer.new(@message).as_json,
          message: "Reaction updated successfully"
        }, status: :ok
      end

      private

      # =========================================================
      # CONVERSATION
      # =========================================================
      def set_conversation
        conversation_id = params[:conversation_id].to_s.strip

        Rails.logger.info(
          "[MessagesController#set_conversation] " \
          "conversation_id=#{conversation_id} " \
          "current_user=#{@current_user.id}"
        )

        begin
          @conversation = Conversation.any_of(
            { user_id: @current_user.id },
            { participant_ids: @current_user.id.to_s }
          ).find(conversation_id)

          Rails.logger.info(
            "[MessagesController#set_conversation] FOUND " \
            "conversation=#{@conversation.id}"
          )

        rescue Mongoid::Errors::DocumentNotFound,
               Mongoid::Errors::InvalidFind,
               BSON::Error::InvalidObjectId => e

          Rails.logger.error(
            "[MessagesController#set_conversation] FAILED " \
            "#{e.class}: #{e.message}"
          )

          @conversation = nil
        end

        return if @conversation.present?

        render json: {
          success: false,
          error: "Conversation not found"
        }, status: :not_found
      end

      # =========================================================
      # MESSAGE
      # =========================================================
      def set_message
        message_id = params[:message_id] || params[:id]

        Rails.logger.info(
          "[MessagesController#set_message] " \
          "message_id=#{message_id}"
        )

        @message = @conversation.messages.find(message_id)

        current_user_id = @current_user.id.to_s

        allowed =
          @conversation.user_id.to_s == current_user_id ||
          Array(@conversation.participant_ids)
            .map(&:to_s)
            .include?(current_user_id)

        unless allowed
          Rails.logger.warn(
            "[MessagesController#set_message] ACCESS DENIED " \
            "user=#{current_user_id}"
          )

          return render json: {
            success: false,
            error: "Message not found or access denied"
          }, status: :not_found
        end

      rescue Mongoid::Errors::DocumentNotFound => e
        Rails.logger.error(
          "[MessagesController#set_message] NOT FOUND #{e.message}"
        )

        render json: {
          success: false,
          error: "Message not found"
        }, status: :not_found
      end

      # =========================================================
      # FIND SENDER
      # =========================================================
      def find_sender
        if @current_user.present?
          Rails.logger.info(
            "[MessagesController#find_sender] " \
            "sender=#{@current_user.id}"
          )

          return @current_user
        end

        Rails.logger.error(
          "[MessagesController#find_sender] Missing current user"
        )

        render json: {
          success: false,
          error: "Sender missing"
        }, status: :bad_request

        nil
      end

      # =========================================================
      # NORMALIZE ATTACHMENT TYPE
      # =========================================================
      def normalize_attachment_type(attachment_type)
        return nil if attachment_type.blank?

        type = attachment_type.to_s.downcase.strip

        # Remove codec params
        # "audio/webm;codecs=opus" => "audio/webm"
        type = type.split(";").first.strip

        return "pdf" if type == "application/pdf"

        if type.include?("/")
          category = type.split("/").first

          return category if %w[
            audio
            image
            video
          ].include?(category)
        end

        return type if %w[
          audio
          image
          video
          pdf
          other
        ].include?(type)

        Rails.logger.warn(
          "[MessagesController] Unknown attachment type=#{attachment_type}"
        )

        "other"
      end

      # =========================================================
      # STRONG PARAMS
      # =========================================================
      def message_params
        params.require(:message).permit(
          :content,
          :user_id,
          :school_id,
          :name,
          :schoolName,
          :attachment_url,
          :attachment_type,
          :attachment_name,
          :attachment_size
        )
      end

      # =========================================================
      # SERIALIZER
      # =========================================================
      def serialize_message(message)
        MessageSerializer.new(message).as_json
      end
    end
  end
end