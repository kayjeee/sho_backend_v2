# frozen_string_literal: true

class NotificationService
  OFFLINE_THRESHOLD = 30.seconds

  def initialize(api_key: ENV.fetch("COURIER_API_KEY"))
    @client = Trycourier::Client.new(api_key: api_key)
  end

  def self.send_message_push(recipient, sender, content)
    new.send_message_push(recipient, sender, content)
  end

  def self.send_push(recipient, message)
    new.send_push(recipient, message)
  end

  def self.send_push_notification(user, message_content)
    new.send_push_notification(user, message_content)
  end

  def send_push(recipient, message)
    return nil unless offline?(recipient)

    send_push_notification(recipient, message)
  end

  def send_push_notification(user, message_content)
    send_message_push(user, nil, message_content)
  end

  def send_message_push(recipient, sender, content)
    response = @client.send_.message(
      message: {
        to: {
          user_id: recipient.id.to_s
        },
        template: courier_template_id,
        data: {
          message_content: content.to_s,
          content: content.to_s,
          recipient_name: recipient.display_name,
          sender_name: sender_name(sender)
        }
      }
    )

    Rails.logger.info(
      "[NotificationService] Sent Courier push user=#{recipient.id} " \
      "courier_request_id=#{response.respond_to?(:request_id) ? response.request_id : response.inspect}"
    )

    response
  rescue KeyError => e
    Rails.logger.error("[NotificationService] Config error: #{e.message}")
    nil
  rescue Trycourier::Errors::APIConnectionError => e
    Rails.logger.error(
      "[NotificationService] Courier connection error user=#{recipient&.id}: #{e.message}"
    )
    nil
  rescue Trycourier::Errors::APIError => e
    Rails.logger.error(
      "[NotificationService] Courier API error user=#{recipient&.id}: #{e.message}"
    )
    nil
  end

  private

  def courier_template_id
    ENV.fetch("COURIER_TEMPLATE_ID")
  end

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
end
