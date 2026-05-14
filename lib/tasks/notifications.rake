# frozen_string_literal: true

namespace :notifications do
  desc "Send a test Courier push notification to USER_ID with optional MESSAGE"
  task test_push: :environment do
    user_id = ENV["USER_ID"] || ENV["user_id"]
    message = ENV["MESSAGE"] || "Test push notification from Rails console"

    unless user_id.present?
      abort "Usage: bin/rails notifications:test_push USER_ID=<user_id> MESSAGE='Optional message'"
    end

    user = User.find(user_id)
    response = NotificationService.send_push_notification(user, message)

    puts(
      response ?
      "Sent test push notification to user #{user.id}" :
      "Notification send returned nil; check Rails logs for details"
    )
  end
end
