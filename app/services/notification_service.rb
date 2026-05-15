# frozen_string_literal: true

require "httparty"

class NotificationService
  include HTTParty

  base_uri "https://api.courier.com"

  OFFLINE_THRESHOLD = 35.seconds

  def initialize(api_key: ENV.fetch("COURIER_API_KEY", nil))
    @api_key = api_key

    if @api_key.blank?
      Rails.logger.warn(
        "[NotificationService] COURIER_API_KEY missing. Push disabled."
      )
    end
  end

  # =========================================================
  # CLASS METHODS
  # =========================================================

  def self.send_message_push(recipient, sender, content)
    new.send_message_push(recipient, sender, content)
  end

  def self.send_push(recipient, message)
    new.send_push(recipient, message)
  end

  def self.send_push_notification(user, message_content)
    new.send_push_notification(user, message_content)
  end

  # =========================================================
  # PUBLIC METHODS
  # =========================================================

  def send_push(recipient, message)
    return nil unless offline?(recipient)

    send_push_notification(recipient, message)
  end

  def send_push_notification(user, message_content)
    send_message_push(user, nil, message_content)
  end

  def send_message_push(recipient, sender, content)
    return nil unless courier_configured?
    return nil unless offline?(recipient)

    response = self.class.post(
      "/send",
      headers: courier_headers,
      body: courier_payload(
        recipient: recipient,
        sender: sender,
        content: content
      ).to_json
    )

    log_response(response, recipient)

    response
  rescue StandardError => e
    Rails.logger.error(
      "[NotificationService] Push failed user=#{recipient&.id} " \
      "error=#{e.class} message=#{e.message}"
    )

    nil
  end

  private

  # =========================================================
  # COURIER CONFIG
  # =========================================================

  def courier_headers
    {
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type" => "application/json"
    }
  end

  def courier_payload(recipient:, sender:, content:)
    {
      message: {
        to: {
          user_id: recipient.auth0_id.to_s
        },

        template: courier_template_id,

        data: {
          message_content: content.to_s,
          content: content.to_s,
          recipient_name: recipient.try(:display_name),
          sender_name: sender_name(sender)
        }
      }
    }
  end

  def courier_template_id
    ENV.fetch("COURIER_TEMPLATE_ID", nil)
  end

  def courier_configured?
    if @api_key.blank?
      Rails.logger.warn(
        "[NotificationService] Missing COURIER_API_KEY"
      )
      return false
    end

    if courier_template_id.blank?
      Rails.logger.warn(
        "[NotificationService] Missing COURIER_TEMPLATE_ID"
      )
      return false
    end

    true
  end

  # =========================================================
  # HELPERS
  # =========================================================

  def sender_name(sender)
    return "Someone" unless sender

    sender.try(:display_name).presence ||
      sender.try(:name).presence ||
      "Someone"
  end

  def offline?(recipient)
    recipient.last_seen_at.nil? ||
      recipient.last_seen_at < OFFLINE_THRESHOLD.ago
  end

  def log_response(response, recipient)
    if response.success?
      Rails.logger.info(
        "[NotificationService] Push sent user=#{recipient.id} " \
        "response=#{response.body}"
      )
    else
      Rails.logger.error(
        "[NotificationService] Courier error user=#{recipient.id} " \
        "status=#{response.code} body=#{response.body}"
      )
    end
  end
end