class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation_id = params[:conversation_id] || params[:id]
    conversation = Conversation.find_by(id: conversation_id)

    if conversation && current_user && conversation.participant?(current_user)
      stream_from "conversation_#{conversation.id}"
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end
end