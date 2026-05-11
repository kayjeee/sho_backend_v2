# frozen_string_literal: true

# app/services/notification_service.rb
#
# Sends a push/channel notification via Courier when a new message
# is created and the recipient appears to be offline.
#
# Usage (called from SendMessageNotificationJob):
#   NotificationService.call(message)
#
# Environment variables required:
#   COURIER_API_KEY       — your Courier auth token
#   COURIER_TEMPLATE_ID   — the Courier template to trigger
#
class NotificationService
  # A recipient is considered "offline" if they haven't been seen in
  # the last OFFLINE_THRESHOLD_SECONDS seconds.
  OFFLINE_THRESHOLD_SECONDS = 30

  # Entry point — always call this, never instantiate directly.
  def self.call(message)
    new(message).call
  end

  def initialize(message)
    @message = message
  end

  def call
    recipients = resolve_recipients
    return if recipients.empty?

    recipients.each do |recipient|
      next unless offline?(recipient)

      send_notification(recipient)
    end
  rescue => e
    # Never let a notification failure bubble up and affect the user experience.
    Rails.logger.error(
      "[NotificationService] Unexpected error for message=#{@message.id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  private

  # ─── Recipients ────────────────────────────────────────────────────────────

  # Resolves the list of Users who should receive a notification.
  # For a 1-on-1 conversation this is everyone except the sender.
  # For a group this is all participants except the sender.
  def resolve_recipients
    conversation = @message.conversation
    return [] unless conversation

    participant_ids = Array(conversation.participant_ids)
      .map(&:to_s)
      .reject { |id| id == @message.sender_id.to_s }

    return [] if participant_ids.empty?

    User.in(id: participant_ids).to_a
  rescue => e
    Rails.logger.error(
      "[NotificationService] Failed to resolve recipients " \
      "for message=#{@message.id}: #{e.message}"
    )
    []
  end

  # ─── Offline check ─────────────────────────────────────────────────────────

  # Returns true if the user has not been seen recently enough to be
  # considered online or in the foreground.
  def offline?(user)
    last_seen = user.last_seen_at
    return true if last_seen.nil? # never seen → treat as offline

    Time.current - last_seen > OFFLINE_THRESHOLD_SECONDS
  end

  # ─── Courier call ──────────────────────────────────────────────────────────

  def send_notification(recipient)
    client = Trycourier::Client.new(api_key: ENV.fetch("COURIER_API_KEY"))

    template_id = ENV.fetch("COURIER_TEMPLATE_ID") do
      raise KeyError, "COURIER_TEMPLATE_ID environment variable is not set"
    end

    response = client.send_.message(
      message: {
        to: {
          user_id: recipient.id.to_s  # must match the Courier user profile ID
        },
        template: template_id,
        data: {
          sender_name:     sender_name,
          conversation_id: @message.conversation_id.to_s,
          content_preview: content_preview,
        }
      }
    )

    Rails.logger.info(
      "[NotificationService] Notified user=#{recipient.id} " \
      "message=#{@message.id} " \
      "courier_request_id=#{response.request_id}"
    )
  rescue KeyError => e
    Rails.logger.error("[NotificationService] Config error: #{e.message}")
  rescue Trycourier::Errors::APIConnectionError => e
    Rails.logger.error(
      "[NotificationService] Courier connection error for " \
      "recipient=#{recipient.id}: #{e.message}"
    )
  rescue Trycourier::Errors::APIError => e
    Rails.logger.error(
      "[NotificationService] Courier API error for " \
      "recipient=#{recipient.id}: #{e.message}"
    )
  end

  # ─── Payload helpers ───────────────────────────────────────────────────────

  def sender_name
    @message.name.presence ||
      @message.sender&.name.presence ||
      "Someone"
  end

  # Returns a short text preview of the message for the notification body.
  # Falls back to a generic string when there is no text content.
  def content_preview
    if @message.content.present?
      @message.content.truncate(100)
    elsif @message.attachment_url.present?
      attachment_label
    else
      "Sent you a message"
    end
  end

  def attachment_label
    case @message.attachment_type
    when "image"  then "Sent an image 📷"
    when "video"  then "Sent a video 🎥"
    when "audio"  then "Sent a voice message 🎤"
    when "pdf"    then "Sent a document 📄"
    else               "Sent an attachment 📎"
    end
  end
end