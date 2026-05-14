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

  OFFLINE_THRESHOLD = 30.seconds

  # Retry up to 3 times with exponential back-off before discarding.
  # This protects against transient Courier outages without flooding
  # the queue on a permanent failure (e.g. bad template ID).
  retry_on Trycourier::Errors::APIConnectionError,
           wait:     :polynomially_longer,
           attempts: 3

  discard_on Trycourier::Errors::APIError do |job, error|
    Rails.logger.error(
      "[SendMessageNotificationJob] Discarding job #{job.job_id} " \
      "after unrecoverable Courier API error: #{error.message}"
    )
  end

  def perform(message_id)
    message = Message.find_by(id: message_id)

    unless message
      Rails.logger.warn(
        "[SendMessageNotificationJob] Message #{message_id} not found — " \
        "it may have been deleted before the job ran. Skipping."
      )
      return
    end

    recipients_for(message).each do |recipient|
      next unless offline?(recipient)

      NotificationService.send_push(
        recipient,
        message_content(message)
      )
    end
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
