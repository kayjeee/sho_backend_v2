# frozen_string_literal: true

# app/jobs/send_message_notification_job.rb
#
# Sends Courier push notifications asynchronously so the Message callback
# never blocks the HTTP response cycle.
#
# The job receives the message ID as a string (not the document itself)
# to avoid serializing a full Mongoid object into the queue backend.
#
# Enqueued by: Message#after_create_commit
# Queue:       :notifications (configure in config/sidekiq.yml if using Sidekiq)
#
class SendMessageNotificationJob < ApplicationJob
  queue_as :notifications

  OFFLINE_THRESHOLD = 35.seconds

  def perform(message_id)
    message = Message.find_by(id: message_id)

    return unless message

    recipients_for(message).each do |recipient|
      next unless offline?(recipient)
      NotificationService.new.send_message_push(recipient, sender_for(message), message_content(message))
    end
  rescue StandardError => e
    Rails.logger.error("[SendMessageNotificationJob] Delivery failed for message #{message_id}: #{e.message}")
  end

  private

  def recipients_for(message)
    conversation = message.conversation
    return [] unless conversation

    participant_ids = Array(conversation.participant_ids)
      .map(&:to_s)
      .reject { |id| id == message.sender_id.to_s }

    User.in(id: participant_ids).to_a
  end

  def offline?(recipient)
    recipient.last_seen_at.nil? ||
      recipient.last_seen_at < OFFLINE_THRESHOLD.ago
  end

  def sender_for(message)
    message.sender ||
      User.find_by(id: message.sender_id)
  end

  def message_content(message)
    if message.content.present?
      message.content.truncate(100)
    elsif message.attachment_url.present?
      "Sent an attachment"
    else
      "Sent you a message"
    end
  end
end
