# app/serializers/message_serializer.rb

class MessageSerializer
  def initialize(message)
    @message = message
  end

  def as_json
    {
      # =====================================================
      # BASIC MESSAGE DATA
      # =====================================================
      id:              @message.id.to_s,
      conversation_id: @message.conversation_id.to_s,

      reply_to_id:      @message.reply_to_id&.to_s,
      reply_to_preview: @message.reply_to_preview,

      content:         @message.content,

      # =====================================================
      # SENDER / USER DATA
      # =====================================================
      sender_id:       @message.sender_id.to_s,
      user_id:         @message.user_id.to_s,
      school_id:       @message.school_id&.to_s,

      name:            @message.name,
      schoolName:      @message.schoolName,

      # =====================================================
      # MESSAGE STATUS
      # =====================================================
      status:          @message.status,
      read:            @message.read,
      is_pinned:       @message.is_pinned,
      starred_by:      Array(@message.starred_by).map(&:to_s),

      # =====================================================
      # REACTIONS
      # =====================================================
      reactions:       @message.reactions || [],

      # =====================================================
      # ATTACHMENTS
      # =====================================================
      # IMPORTANT:
      # Frontend switches on attachment_type.
      #
      # attachment_type == "audio"
      # => render audio player
      #
      # attachment_type == "image"
      # => render image preview
      #
      # attachment_type == "video"
      # => render video player
      #
      # attachment_type == "pdf"
      # => render document preview
      #
      attachment_url:  @message.attachment_url,

      # CRITICAL FIELD:
      # frontend depends on this value
      attachment_type: @message.attachment_type,

      attachment_name: @message.attachment_name,
      attachment_size: @message.attachment_size,

      # =====================================================
      # TIMESTAMPS
      # =====================================================
      created_at:      @message.created_at&.iso8601,
      updated_at:      @message.updated_at&.iso8601
    }
  end
end
