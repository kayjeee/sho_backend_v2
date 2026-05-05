class MessageSerializer
  def initialize(message)
    @message = message
  end

  def as_json
    {
      id:        @message.id.to_s,
      content:   @message.content,
      sender_id: @message.user_id&.to_s || @message.school_id&.to_s,
      user_id:   @message.user_id&.to_s,
      timestamp: @message.created_at,
      read:      @message.read,
      status:    @message.status,
      reactions: @message.reactions || [],
      name:      @message.name,
      schoolName: @message.schoolName,
      attachment_url: @message.attachment_url,
      attachment_type: @message.attachment_type,
      attachment_name: @message.attachment_name,
      attachment_size: @message.attachment_size
    }
  end
end
