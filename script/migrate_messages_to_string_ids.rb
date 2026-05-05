require_relative '../config/environment'

puts "Migrating Message collection to use String IDs for foreign keys..."
count = 0
Message.all.each do |m|
  m.sender_id   = m.sender_id.to_s   if m.sender_id.is_a?(BSON::ObjectId)
  m.receiver_id = m.receiver_id.to_s if m.receiver_id.is_a?(BSON::ObjectId)
  m.user_id     = m.user_id.to_s     if m.user_id.is_a?(BSON::ObjectId)
  m.school_id   = m.school_id.to_s   if m.school_id.is_a?(BSON::ObjectId)

  if m.changed?
    m.save!(validate: false)
    count += 1
  end
end
puts "Successfully migrated #{count} messages."
