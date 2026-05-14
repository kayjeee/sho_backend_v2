# frozen_string_literal: true

class NotificationService
  OFFLINE_THRESHOLD = 30.seconds

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
    client = Trycourier::Client.new(api_key: courier_api_key)

    response = client.send_.message(
      message: {
        to: {
          user_id: user.id.to_s
        },
        template: courier_template_id,
        data: {
          message_content: message_content.to_s,
          recipient_name: user.display_name
        }
      }
    )

    Rails.logger.info(
      "[NotificationService] Sent Courier push user=#{user.id} " \
      "courier_request_id=#{response.respond_to?(:request_id) ? response.request_id : response.inspect}"
    )

    response
  rescue KeyError => e
    Rails.logger.error("[NotificationService] Config error: #{e.message}")
    nil
  rescue Trycourier::Errors::APIConnectionError => e
    Rails.logger.error(
      "[NotificationService] Courier connection error user=#{user.id}: #{e.message}"
    )
    nil
  rescue Trycourier::Errors::APIError => e
    Rails.logger.error(
      "[NotificationService] Courier API error user=#{user.id}: #{e.message}"
    )
    nil
  end

  private

  def courier_api_key
    ENV.fetch("COURIER_API_KEY")
  end

  def courier_template_id
    ENV.fetch("COURIER_TEMPLATE_ID")
  end

  def offline?(recipient)
    recipient.last_seen_at.nil? ||
      recipient.last_seen_at < OFFLINE_THRESHOLD.ago
  end
end
