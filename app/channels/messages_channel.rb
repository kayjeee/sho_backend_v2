# frozen_string_literal: true

class MessagesChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:conversation_id])

    if conversation.nil?
      reject # cleanly refuses the subscription — client receives "rejected" status
      return
    end

    stream_for conversation
  end

  def unsubscribed
    # streams are stopped automatically by ActionCable on disconnect
  end
end