class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.where(id: params[:id]).first

    # Check if user is a participant
    if conversation && (conversation.user_id == current_user.id || conversation.participant_ids.include?(current_user.id.to_s))
      stream_for conversation
    else
      reject
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
